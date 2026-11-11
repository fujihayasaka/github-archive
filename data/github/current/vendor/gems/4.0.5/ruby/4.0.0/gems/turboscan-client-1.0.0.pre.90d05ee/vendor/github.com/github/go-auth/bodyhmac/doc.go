// Package bodyhmac implements a simple HMAC scheme that was inspired by the draft at
// https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12
// In summary:
//   - The code assumes that the header value can contain an HMAC over the request body
//   - This is intended to validate the integrity of the body bytes and not just a timestamp header
//   - The code assumes that the body is never nil - this is intended for RPC-style interactions that rely on POST exclusively
package bodyhmac
