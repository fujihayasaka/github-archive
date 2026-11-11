const stream = require('stream')
const undici = require('undici')
const Package = require('./package')
const log = require('./logger')

const UserAgent = 'Github Dependency Graph NPM PMA'

class PackageTransformer extends stream.Transform {
  constructor (endpoint, options) {
    options.objectMode = true
    super(options)
    this._options = options
    this.endpoint = endpoint
  }

  _transform (change, enc, callback) {
    const packageID = change.id
    const seqID = change.seq

    log(`Fetching package metadata for ${packageID}, seq ${seqID}`)
    fetchPackage(this.endpoint, packageID, seqID).then(packageData => {
      if (packageData) {
        log(`Importing package name '${packageData.fullName}'`)
        this.push(packageData)
      }
      callback()
    }).catch(error => {
      log(`Error importing package ${packageID}: ${error}`)
      throw error
    })
  }
}

module.exports = PackageTransformer

// fetchPackage fetches the metadata for a package from the npm registry
// and returns it in the form of a Package object. It handles rate limiting
// (via 429 responses only). If the package is not found, it returns null.
// This is expected in cases where the package has been deleted.
async function fetchPackage(endpoint, packageID, seqID) {
  const encodedPackageID = encodeURIComponent(packageID);
  const url = `${endpoint}${encodedPackageID}`;
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
      log(`Package ${packageID}, seq ${seqID} is missing the externalId field. Got ${JSON.stringify(data)}`);
      return null;
    }
    return newPackage;

  } else if (statusCode === 429) {
    // Retry after the specified number of seconds
    const retryAfter = headers.get('Retry-After');
    log(`Rate limited by npmjs.com. Retrying after ${retryAfter} seconds`);
    await new Promise(resolve => setTimeout(resolve, retryAfter * 1000));
    return fetchPackage(packageID, seqID);

  } else if (statusCode === 404) {
    log(`Package ${packageID} not found. It may have been deleted.`);
    return null;

  }
  log(`Request failed with status: ${statusCode}`);
  return null;
}
