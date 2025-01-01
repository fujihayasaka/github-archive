# Bootstraps the Tapioca DSL processing by explicitly loading the libraries
# containing protobuf definitions that we'd like to have processed
# See: https://github.com/Shopify/tapioca/issues/442
require "google/protobuf"
require "sigstore_bundle_pb"
require "monolith-twirp-attester"
