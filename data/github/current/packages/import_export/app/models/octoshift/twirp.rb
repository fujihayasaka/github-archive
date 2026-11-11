# typed: true
# frozen_string_literal: true

module Octoshift
  module Twirp
    # The max amount of objects to fetch from Octoshift. This is based on
    # max graphql pagination limit of 100 + 1 to check for further pages
    TWIRP_CURSOR_LIMIT = 101

    class Error < ::RuntimeError; end
    class InvalidCursorError < Error; end
    class CustomerQueueNotFound < Error; end
    class ConnectorNotFound < Error; end
  end
end
