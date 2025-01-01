var query = ace.edit("query");
query.setTheme("ace/theme/textmate");
query.session.setMode("ace/mode/sql");
query.on("change", function() {
  var queryInput = document.querySelector("input[name=query]");
  queryInput.value = query.getValue();
});

document.querySelector('form').addEventListener('submit', function(e) {
  var queryInput = document.querySelector("input[name=query]");
  var queryValue = queryInput.value;

  if (!queryValue.trim()) {
    alert("Query cannot be empty");
    e.preventDefault(); // prevent the form from being submitted
  }
});

var results = ace.edit("results");
results.setTheme("ace/theme/textmate");
results.session.setMode("ace/mode/json");
results.setReadOnly(true);