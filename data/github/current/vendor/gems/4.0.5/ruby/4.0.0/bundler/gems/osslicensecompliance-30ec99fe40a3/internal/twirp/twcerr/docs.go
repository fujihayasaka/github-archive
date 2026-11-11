// Package twcerr defines custom Twirp errors shared across server and clients.
//
// # Creating or modifying an error
//
// Each custom error lives in its own file under internal/twirp/twcerr/.
// The file name is the source-of-truth for the error "name":
//
//   - Error files are identified by file name format: `*_error.go`
//   - Error meta field value: The <file_name> without extension becomes the stable meta field value stored in `err.Meta['error_name']`
//   - Constructor: The <file_name> without extension converted to PascalCase becomes the name of the Go constructor function
//
// For example, internal/twirp/twcerr/invalid_spdx_identifiers_error.go corresponds to:
//   - MetaErrorName value: "invalid_spdx_identifiers_error"
//   - Go Constructor function: NewInvalidSPDXIdentifiersError(...)
//
// # Adding new errors
//
// It is OK (and expected) to add new custom errors. When adding a new error:
//  1. Create a new <custom_error_name>_error.go file and associated <custom_error_name>_error_test.go file
//  2. Implement constructor with name following the convention described above for `Constructor:`
//     (e.g. `NewInvalidSPDXIdentifiersError`) and have it return a customized Twirp error.  See more about
//     the constructor's call to `customizeError` below.
//  3. (optional) Implement any helper functions needed to format error messages or validate input.
//
// The constructor calls `customizeError()` defined in errors.go to decorate
// an existing Twirp error and return the customized error.  The expected parameters are:
//
//   - baseError: The underlying Twirp error (e.g. `twirp.InvalidArgumentError(...)`)
//   - errorName: The name of this error, which MUST be `"<file_name_without_extension>"`
//   - customErrorMsg: A formatted error message string
//   - customMetadata: (optional) A map of additional metadata to include in the error
//
// # Modifying existing errors
//
// It is OK to change the processing/behavior of an existing error (message formatting, validation rules, etc),
// but do NOT change the <file_name> which is the value of `errorName` that is used by the client.  The errorName
// is part of the public API for custom errors and changing them will break clients.
package twcerr
