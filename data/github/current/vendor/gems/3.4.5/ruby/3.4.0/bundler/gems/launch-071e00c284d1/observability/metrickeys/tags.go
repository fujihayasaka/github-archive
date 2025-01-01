package metrickeys

// HTTPResultCategory for a code, e.g "2xx" for 204, or NonHTTPError for errors below level of HTTP
const HTTPResultCategory = "result_category"

// HTTPStatusCode is for a HTTP status code.
const HTTPStatusCode = "status_code"

// ServiceName providing the operation e.g "AZP"
const ServiceName = "service"

// OperationName for a API interaction, e.g "build.get"
const OperationName = "operation"

const Provider = "provider"

// State tags the state of a thing
const State = "state"

// At tags point at which something happened
const At = "at"
