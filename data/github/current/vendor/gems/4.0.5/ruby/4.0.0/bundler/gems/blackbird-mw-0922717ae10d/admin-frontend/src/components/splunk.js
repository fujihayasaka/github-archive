export function getSplunkLink(stamp, query, params) {
  let splunkAccount = getSplunkAccount(stamp);

  let q = `index=blackbird stamp="${stamp}"`;
  q += " " + query;

  let url = `https://${splunkAccount}.githubapp.com/en-US/app/gh_reference_app/search`;
  url += `?q=${encodeURIComponent(q)}`;
  params ||= {};
  params.earliest ||= "-15m@m";
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
  case "prod-cus-01":
    return "splunk-cus";
  case "prod-jpw-01":
    return "splunk-jpw";
  default:
    return "splunk";
  }
}
