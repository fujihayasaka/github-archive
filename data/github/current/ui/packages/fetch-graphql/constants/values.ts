// "SERVICE_UNAVAILABLE" are availability issues. It is allowed as we expect the app code to handle it
export const ALLOWED_ERRORS = ['SAML', 'SERVICE_UNAVAILABLE']
// For some errors, we want to allow them in certain contexts and let the app handle them
export const CONDITIONAL_ALLOWED_ERRORS: Record<string, string[]> = {
  FORBIDDEN: ['SAML error'],
  AUTHENTICATION: ['Couldn’t authenticate you'],
}

export const WILDCARD = '*'

/*
  Allow 'discussion' path as discussion number is received from URL params during issue creation.
  Any value for discussion number could be received via URL params hence the need to allow the NOT_FOUND error.
  Allow missing signer in commits in referenced issue events

  TODO: Consider ALWAYS allowing NOT_FOUND errors and let client code handle them at the presentation level
*/
export const CONDITIONAL_ALLOWED_PATHS: Record<string, string[][]> = {
  NOT_FOUND: [
    ['repository', 'discussion'],
    ['repository', 'issue', '*', 'edges', '*', 'node', 'commit', 'signature', 'signer'],
    ['node', '*', 'edges', '*', 'node', 'commit', 'signature', 'signer'],
  ],
}
