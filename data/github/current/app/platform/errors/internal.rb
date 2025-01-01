# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    # Private: `Internal` errors and sub-classes of this error are used to raise
    # fatal exceptions within `Platform` that should not be exposed to GraphQL
    # consumers.
    class Internal < StandardError; end
  end
end
