# typed: true
# frozen_string_literal: true

require "minitest/autorun"
require "debug"
require "faraday"

# Register the test adapter
Faraday::Adapter.register_middleware(test: Faraday::Adapter::Test)
