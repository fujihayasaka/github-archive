const stream = require('stream')
const undici = require('undici')
const Package = require('./package')
const log = require('./logger')

const UserAgent = 'Github Dependency Graph NPM PMA'
const PackageMetadataAPI = 'https://replicate.npmjs.com/registry/'

module.exports = new stream.Transform({
  objectMode: true,

  transform (change, enc, callback) {
    const packageID = change.id
    const seqID = change.seq

    log(`Fetching package metadata for ${packageID}, seq ${seqID}`)
    fetchPackage(packageID, seqID).then(package => {
      if (package) {
        log(`Importing package name '${package.fullName}'`)
        this.push(package)
      }
      callback()
    }).catch(error => {
      console.error(`Error importing package ${packageID}: ${error}`)
      throw error
    })
}})

// fetchPackage fetches the metadata for a package from the npm registry
// and returns it in the form of a Package object. It handles rate limiting
// (via 429 responses only). If the package is not found, it returns null.
// This is expected in cases where the package has been deleted.
async function fetchPackage(packageID, seqID) {
  const url = packageMetadataPath(packageID);
  const {
    statusCode,
    headers,
    body
  } = await undici.request(url, {
    method: 'GET',
    headers: {
      'User-Agent': UserAgent
    },
    maxRedirections: 5
  })
  if (statusCode === 200) {
    const data = await body.json();
    const newPackage = new Package(data, seqID);
    if (!newPackage.externalId) {
      console.warn(`Package ${packageID}, seq ${seqID} is missing the externalId field. Got ${JSON.stringify(data)}`);
      return null;
    }
    return newPackage;

  } else if (statusCode === 429) {
    // Retry after the specified number of seconds
    const retryAfter = headers.get('Retry-After');
    console.warn(`Rate limited by npmjs.com. Retrying after ${retryAfter} seconds`);
    await new Promise(resolve => setTimeout(resolve, retryAfter * 1000));
    return fetchPackage(packageID, seqID);

  } else if (statusCode === 404) {
    console.warn(`Package ${packageID} not found. It may have been deleted.`);
    return null;

  }
  console.warn(`Request failed with status: ${statusCode}`);
  return null;
}

// packageMetadataPath returns the URL for the metadata of a package
// with the given packageID. The main reason for this helper is to
// ensure that the packageID is properly encoded.
function packageMetadataPath(packageID) {
  const encodedPackageID = encodeURIComponent(packageID);
  return `${PackageMetadataAPI}${encodedPackageID}`;
}
