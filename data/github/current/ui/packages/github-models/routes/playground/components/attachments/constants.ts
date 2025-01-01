export const MAX_ATTACHMENT_COUNT = 3
export const ACCEPTED_MIME = ['image/*']
// NOTE: There is a string representation of in an error message, if you want to update — check that too
export const MAX_ATTACHMENT_SIZE = 1 * 1024 * 1024 // 1MB

export const ACCEPTED_MIME_REGEX = ACCEPTED_MIME.map(type => new RegExp(type.replace(/\*/g, '.*')))
