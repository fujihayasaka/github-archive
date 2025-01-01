// "SERVICE_UNAVAILABLE" are availability issues. It is allowed as we expect the app code to handle it
export const ALLOWED_ERRORS = ['SAML', 'SERVICE_UNAVAILABLE']
// For some errors, we want to allow them in certain contexts and let the app handle them
export const CONDITIONAL_ALLOWED_ERRORS: Record<string, string[]> = {
  FORBIDDEN: ['SAML error'],
  AUTHENTICATION: ['Couldn’t authenticate you'],
}

/*
  Allow 'discussion' path as discussion number is received from URL params during issue creation.
  Any value for discussion number could be received via URL params hence the need to allow the NOT_FOUND error.
*/
export const CONDITIONAL_ALLOWED_PATHS: Record<string, string[]> = {
  NOT_FOUND: ['repository', 'discussion'],
}
