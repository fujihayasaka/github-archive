export function getSplunkLink(app, corpus, query, stamp, params) {
  let splunkAccount = getSplunkAccount(stamp);

  let q = `index=blackbird stamp="${stamp}" app="${app}"`;
  if (corpus) {
    q += " corpus=" + corpus.corpus_name;
  }
  q += " " + query;

  let url = `https://${splunkAccount}.githubapp.com/en-US/app/gh_reference_app/search`;
  url += `?q=${encodeURIComponent(q)}`;
  params ||= {};
  params.earliest ||= "-24h@h";
  params.latest ||= "now";
  for (const [key, value] of Object.entries(params)) {
    url += `&${encodeURIComponent(key)}=${encodeURIComponent(value)}`;
  }

  return url;
}

function getSplunkAccount(stamp) {
  switch(stamp) {
  case "prod-weu-01":
  case "prod-sdc-01":
    return "splunk-eu";
  case "prod-ae-01":
    return "splunk-ae";
  default:
    return "splunk";
  }
}
