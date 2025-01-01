const commitRangeRegex = /^(?<startOid>[a-fA-F0-9]{7,40})\.\.(?<endOid>[a-fA-F0-9]{7,40})$/
const commitOidRegex = /^[a-fA-F0-9]{7,40}$/

/**
 * Takes potential URL commit data and returns the commit range, the commit oid, or undefined if commit
 * data cannot be parsed.
 *
 * @param commitData Expected format of {startOid}..{endOid} or just a commit OID
 */
export function parseCommitRange(
  commitRange: string,
): {startOid: string; endOid: string} | {singleCommitOid: string} | undefined {
  const range = commitRange.match(commitRangeRegex)
  const startOid = range?.groups?.['startOid']
  const endOid = range?.groups?.['endOid']
  if (range && startOid && endOid) {
    return {startOid, endOid}
  } else if (commitOidRegex.test(commitRange)) {
    return {singleCommitOid: commitRange}
  } else {
    return undefined
  }
}
