// reqobs is a package that emits a standardized set of telemetry for outgoing requests.
//
// # Introduction
//
// In past iterations of Launch, clients were usually responsible for their own telemetry. Meaning that
// each bespoke HTTP wrapper implemented its telemetry emission slightly differently, leading to large
// amounts of variance.  By using the hooks provided by this package, various clients can converge on
// the same telemetry topology.
//
// # Metric Topology
//
// The metric topology spans a few metric keys and includes a few well-known tags both defined as package
// level constants. It's important that hooks in reqobs fulfill these expectations, and therefore,
// efforts have been made to create helper functions that can be called to avoid duplicating this logic.
// Unfortunately, there is still a great deal of variance between clients, and so the building of tags is
// left to the individual hooks.
package reqobs
