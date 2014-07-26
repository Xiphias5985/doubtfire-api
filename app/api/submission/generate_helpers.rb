module Api::Submission::GenerateHelpers
  
  #
  # Scoops out a files array from the params provided
  #
  def scoop_files(params, upload_reqs)
    files = params.reject { | key | not key =~ /^file\d+$/ }

    error!({"error" => "Upload requirements mismatch with files provided"}, 403) if files.length != upload_reqs.length 
    #
    # Pair the name and type from upload_requirements to each file
    #
    upload_reqs.each do | detail |
      key = detail['key']
      if files.has_key? key
        files[key].id   = files[key].name
        files[key].name = detail['name']
        files[key].type = detail['type']
      end
    end
    
    # File didn't get assigned an id above, then reject it since there was a mismatch
    files = files.reject { | key, file | file.id.nil? }
    error!({"error" => "Upload requirements mismatch with files provided"}, 403) if files.length != upload_reqs.length 

    # Kill the kvp
    files.map{ | k, v | v }
  end
  
  #
  # Combines image, code or documents files given to pdf.
  # Returns the tempfile that was generated. 
  #
  # It is the caller's responsibility to delete this tempfile
  # once the method is finished.
  #
  def combine_to_pdf(files)
    #
    # Ensure that each file in files has the following attributes:
    # id, name, filename, type, tempfile  
    #
    files.each do | file |
      error!({"error" => "Missing file data for '#{file.name}'"}, 403) if file.id.nil? || file.name.nil? || file.filename.nil? || file.type.nil? || file.tempfile.nil?
    end
    
    #
    # Output files should store *directory* paths of output files
    # Need to store the final_pdf on the file server somewhere?
    #
    pdf_paths = []
    final_pdf = Tempfile.new(["output", ".pdf"])

    #
    # Confirm subtype categories using filemagic (exception handling
    # must be done outside multithreaded environment below...)
    #
    files.each do | file |
      fm = FileMagic.new(FileMagic::MAGIC_MIME)
      mime = fm.file file.tempfile.path

      case file.type
      when 'image'
        accept = ["image/png", "image/gif", "image/bmp", "image/tiff", "image/jpeg"]
      when 'code'
        accept = ["text/x-pascal", "text/x-c", "text/x-c++", "text/plain"]
      when 'document'
        accept = ["application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                  "application/msword", "application/pdf"]
      else
        error!({"error" => "Unknown type '#{file.type}' provided for '#{file.name}'"}, 403)
      end
      
      if not mime.start_with?(*accept)
        error!({"error" => "'#{file.name}' was not an #{file.type} file type"}, 403)
      end
    end
    
    #
    # Convert each file concurrently... Ruby arrays are NOT thread safe, so we
    # must push output files to the pdf_paths array atomically
    #
    pdf_paths_mutex = Mutex.new
    files.each_with_index.map do | file, idx |
      Thread.new do         
        #
        # Create dual output documents (coverpage and document itself)
        #
        coverp_file = Tempfile.new(["#{idx}.cover", ".pdf"])
        output_file = Tempfile.new(["#{idx}.data", ".pdf"])
                  
        #
        # Make file coverpage
        #
        coverpage_data = { "Filename" => "<pre>#{file.filename}</pre>", "Document Type" => file.type.capitalize, "Upload Timestamp" => DateTime.now.strftime("%F %T"), "File Number" => "#{idx+1} of #{files.length}" }
        coverpage_body = "<h1>#{file.name}</h1>\n<dl>"
        coverpage_data.each do | key, value |
          coverpage_body << "<dt>#{key}</dt><dd>#{value}</dd>\n"
        end
        coverpage_body << "</dl><footer>Generated with Doubtfire</footer>"
        
        kit = PDFKit.new(coverpage_body, :page_size => 'A4', :margin_top => "30mm", :margin_right => "30mm", :margin_bottom => "30mm", :margin_left => "30mm")
        kit.stylesheets << "vendor/assets/stylesheets/doubtfire-coverpage.css"
        kit.to_file coverp_file.path

        #
        # File -> PDF
        #  
        case file.type
        #
        # img -> pdf
        #
        when 'image'
          img = Magick::Image.read(file.tempfile.path).first
          # resize the image if its too big (e.g., taken with a digital camera)
          if img.columns > 1000 || img.rows > 500
            # resize such that it's 600px in width
            scale = 1000.0 / img.columns
            img = img.resize(scale)
          end
          img.write("pdf:#{output_file.path}") { self.quality = 75 }
        #
        # code -> html -> pdf
        #
        when 'code'
          # decide language syntax highlighting
          case File.extname(file.filename)
          when '.cpp', '.cs'
            lang = :cplusplus
          when '.c', '.h'
            lang = :c
          when '.java'
            lang = :java
          when '.pas'
            lang = :delphi
          else
            # should follow basic C syntax (if, else etc...)
            lang = :c
          end
          
          # code -> HTML
          html_body = CodeRay.scan_file(file.tempfile, lang).html(:wrap => :div, :tab_width => 2, :css => :class, :line_numbers => :table, :line_number_anchors => false)

          # HTML -> PDF
          kit = PDFKit.new(html_body, :page_size => 'A4', :header_left => file.filename, :header_right => "[page]/[toPage]", :margin_top => "10mm", :margin_right => "5mm", :margin_bottom => "5mm", :margin_left => "5mm")
          kit.stylesheets << "vendor/assets/stylesheets/coderay.css"
          kit.to_file output_file.path
        #
        # document -> pdf
        #
        when 'document'
          # if uploaded a PDF, then directly pass in
          if File.extname(file.filename) == '.pdf'
            # copy the file over (note we need to copy it into
            # output_file as file will be removed at the end of this block)
            FileUtils.cp file.tempfile.path, output_file.path
          else
          # TODO: convert word -> pdf
            error!({"error" => "Currently, word documents are not supported. Convert the document to PDF first."}, 403)
          end
        end
        
        # Insert (at appropriate index) the converted PDF and its coverpage to pdf_paths array (lock first!)...
        pdf_paths_mutex.synchronize do
          pdf_paths[idx] = [coverp_file.path, output_file.path]
        end
        
        # I can now delete this uploaded file
        file.tempfile.unlink
      end
    end.each { | thread | thread.join }
    
    #
    # Aggregate each of the output PDFs
    #
    didCompile = system "pdftk #{pdf_paths.join ' '} cat output #{final_pdf.path}"
    if !didCompile 
      error!({"error" => "PDF failed to compile. Please try again."}, 403)
    end
    
    # We don't need any of those pdf_paths files anymore after compiling the final_pdf!
    pdf_paths.each { | path | FileUtils.rm path } 
    
    # We need to do something with this... so we'll let the caller handle that.
    final_pdf
  end
  
  module_function :combine_to_pdf
  module_function :scoop_files
  
end