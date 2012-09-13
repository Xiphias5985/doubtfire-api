$(document).ready(function() {
  $.each($(".status-distribution-chart"), function(i, statusDistributionContainer) {
    constructStatusDistributionChart(statusDistributionContainer);
  });
});

function constructStatusDistributionChart(statusDistributionContainer) 
{
  var projectJSONURL = $(statusDistributionContainer).attr("data-url");

  d3.json(projectJSONURL, function(projectJSON) {
    if(projectJSON.status_distribution.total == 0) return;

    var distributionData = statusDistributionDataForProjectJSON(projectJSON);

    nv.addGraph(function() {  
      var width = 150,
          height = 150;

      var colours = [
        colourForProjectProgress("ahead"),
        colourForProjectProgress("on_track"),
        colourForProjectProgress("behind"),
        colourForProjectProgress("danger"),
        colourForProjectProgress("doomed"),
        colourForProjectProgress("not_started")
      ];

      var statusDistributionChart = nv.models.pieChart()
          .x(function(d) { return d.label })
          .y(function(d) { return d.value })
          .color(colours)
          .showLabels(false)
          .showLegend(false);

      d3.select($(statusDistributionContainer).children("svg")[0])
          .datum(distributionData)
        .transition().duration(1200)
          .call(statusDistributionChart);

      statusDistributionChart.tooltipContent(function(key, y, e, graph){
        return "<h3>" + "Status Distribution" + "</h3>"
        + "<p>" + parseFloat(y).toFixed() + " project(s) '" + key + "'</p>";
      });

      return statusDistributionChart;
    });
  });
}

function colourForProjectProgress(progress)  {
  var colour = null;

  switch (progress)
  {
    case "ahead":
      colour = "#48842c"; // Twitter Bootstrap @green
      break;
    case "on_track":
      colour = "#049cdb"; // Twitter Bootstrap @blue
      break;
    case "behind":
      colour = "#f89406"; // Twitter Bootstrap @orange
      break;
    case "danger":
      colour = "#9d261d"; // Twitter Bootstrap @red
      break;
    case "doomed":
      colour = "#000000";
      break;
    case "not_started":
      colour = "#888888";
      break;
  }

  return colour;
}

function statusDistributionDataForProjectJSON(project) {
  var statusDistributions = [
    {
      key: "Status",
        values: [
          { 
            "label" : "Going Well",
            "value" : project.status_distribution.ahead
          }, 
          { 
            "label" : "Progressing", 
            "value" : project.status_distribution.on_track
          }, 
          { 
            "label" : "Need to Catch Up",
            "value" : project.status_distribution.behind
            
          }, 
          { 
            "label" : "Seek Help",
            "value" : project.status_distribution.danger
            
          }, 
          { 
            "label" : "Running Out of Time",
            "value" : project.status_distribution.doomed
            
          },
          { 
            "label" : "Not Started",
            "value" : project.status_distribution.not_started
          }
        ]
      } 
  ];

  return statusDistributions;
}