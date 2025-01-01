# typed: true
# frozen_string_literal: true

require "graphql/client"

module PlatformHelper
  # Single constant definition
  # This is in its own file so that we can autoload it only when needed.
  PlatformClient = GraphQL::Client.new(
    schema: Platform::Schema,
    execute: PlatformExecute,
    enforce_collocated_callers: false
  )
end
