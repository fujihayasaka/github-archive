// Makes sure we don't show the ultra long path, but rather just the path that's relevant to the user.
// Turns /home/runner/work/sweagentd/sweagentd/src/app/App.tsx into src/app/App.tsx.

export function trimFileName(path: string): string | undefined {
  try {
    const shortenedPath = path.replace('/home/runner/work/', '').split('/').slice(2).join('/')
    return shortenedPath.length > 0 ? shortenedPath : undefined // Special-case the root when viewing the repo, we handle outside
  } catch {
    return path
  }
}
