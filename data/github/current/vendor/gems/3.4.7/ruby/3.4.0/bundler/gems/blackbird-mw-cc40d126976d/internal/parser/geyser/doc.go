// Package geyser includes query parsing code extracted from the [Geyser]
// project. It is used to parse legacy code search queries so they can be
// translated to Blackbird.
//
// The code in this package comes from Geyser's [search/transport] package, but
// has been flattened into a single package and in some cases lightly edited to
// reduce filename ambiguity with Blackbird files.
//
// To generate the PEG parser, run script/gogenerate.
//
// [Geyser]: https://github.com/github/geyser
// [search/transport]: https://github.com/github/geyser/tree/master/search/transport
package geyser
