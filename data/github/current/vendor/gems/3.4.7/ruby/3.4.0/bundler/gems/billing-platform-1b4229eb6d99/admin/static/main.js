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

function showShareableLink(shareableURL) {
  const shareableLinkInput = document.getElementById('shareableLinkInput');
  shareableLinkInput.value = window.location.origin + shareableURL;

  document.getElementById('shareButton').style.display = 'none';
  document.getElementById('shareableLink').style.display = 'block';
}

function copyToClipboard(event) {
  var copyButton = event.target;
  copyButton.textContent = "Copied!";
  setTimeout(() => {
    copyButton.textContent = "Copy";
  }, 2000);

  var copyText = document.getElementById("shareableLinkInput");
  copyText.select();
  navigator.clipboard.writeText(copyText.value)
}
