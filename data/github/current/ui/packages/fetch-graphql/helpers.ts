import {CONDITIONAL_ALLOWED_PATHS, WILDCARD} from './constants/values'

export function checkConditionalAllowedPaths(errorType: string, path: Array<string | number>) {
  const allowedPaths = CONDITIONAL_ALLOWED_PATHS[errorType]
  if (!allowedPaths) {
    return false
  }

  for (const allowedPath of allowedPaths) {
    if (path.length !== allowedPath.length) continue

    let foundMatchingPath = true
    for (let i = 0; i < path.length; i++) {
      if (path[i] !== allowedPath[i] && allowedPath[i] !== WILDCARD) {
        foundMatchingPath = false
        break
      }
    }
    if (foundMatchingPath) {
      return true
    }
  }

  return false
}
