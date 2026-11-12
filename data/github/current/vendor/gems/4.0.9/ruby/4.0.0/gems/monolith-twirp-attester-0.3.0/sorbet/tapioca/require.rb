# typed: true
# frozen_string_literal: true

require "base64"
require "faraday"
require "google/protobuf"
require "in_toto_attestation/v1/statement_pb"
require "minitest/autorun"
require "minitest/snapshots"
require "net/http"
require "openssl"
require "pry"
require "sigstore_bundle_pb"
require "sorbet-runtime"
require "twirp"
require "vcr"
require "webmock/minitest"
require "yaml"
