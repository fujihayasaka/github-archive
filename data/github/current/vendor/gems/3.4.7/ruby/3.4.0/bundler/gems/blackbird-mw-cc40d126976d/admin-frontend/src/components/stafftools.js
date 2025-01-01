export function getStafftoolsLink(stamp, slug) {
  let stampWithoutSeparators = stamp.replace(/-/g, '');
  switch(stamp) {
    case "dotcom":
      return `https://admin.github.com/stafftools/${slug}`;
    case "staff-wus2-01":
      let staffStampURI = encodeURIComponent(`https://stafftoolswus2.ghe.com/stafftools/${slug}`);
      return `https://jit-okta-bouncer.githubapp.com/stafftoolswus2?redirect=${staffStampURI}`;
    default:
      let genericStampURI = encodeURIComponent(`https://stafftools-${stampWithoutSeparators}.ghe.com/stafftools/${slug}`);
      return `https://jit-okta-bouncer.githubapp.com/stafftools-${stampWithoutSeparators}?redirect=${genericStampURI}`;
    }
}
