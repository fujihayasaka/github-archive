/**
 * Base pull request URL
 * Equivalent to the "conversations" tab in Rails
 */
export function pullRequestUrl({
  owner,
  repoName,
  number,
}: {
  owner: string | undefined
  repoName: string | undefined
  number: string | undefined
}) {
  if (!owner || !repoName || !number) throw new Error('Cannot generate pull request url')

  return `/${owner}/${repoName}/pull/${number}`
}

/**
 * Pull Request Files changed URL
 */
export function pullRequestFilesChangedUrl(args: {
  owner: string | undefined
  repoName: string | undefined
  number: string | undefined
  singleCommitOid?: string | undefined | null
}): string
export function pullRequestFilesChangedUrl(args: {
  owner: string | undefined
  repoName: string | undefined
  number: string | undefined
  startOid?: string | undefined | null
  endOid?: string | undefined | null
}): string
export function pullRequestFilesChangedUrl({
  owner,
  repoName,
  number,
  startOid,
  endOid,
  singleCommitOid,
}: {
  owner: string | undefined
  repoName: string | undefined
  number: string | undefined
  startOid?: string | undefined | null
  endOid?: string | undefined | null
  singleCommitOid?: string | undefined | null
}): string {
  let url = `${pullRequestUrl({owner, repoName, number})}/files`

  if (singleCommitOid) {
    url += `/${singleCommitOid}`
  } else if (startOid && endOid) {
    url += `/${startOid}..${endOid}`
  }

  return url
}

/**
 * Pull Request activity view URL
 */
export function pullRequestActivityUrl({
  owner,
  repoName,
  number,
}: {
  owner: string | undefined
  repoName: string | undefined
  number: string | undefined
}) {
  return `${pullRequestUrl({owner, repoName, number})}/activity`
}

/**
 * Pull Request activity view URL
 */
export function pullRequestCommitsUrl({
  owner,
  repoName,
  number,
}: {
  owner: string | undefined
  repoName: string | undefined
  number: string | undefined
}) {
  return `${pullRequestUrl({owner, repoName, number})}/commits`
}
