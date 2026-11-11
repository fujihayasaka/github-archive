# typed: true
# frozen_string_literal: true

module GitHub
  module Sweagentd
    # The Sweagentd Client provides access to various SWE Agent APIs.
    # Each API is implemented as a separate client in the client/ subdirectory.
    class Client
      autoload :Jobs, "github/sweagentd/client/jobs"

      # Initialize a new Sweagentd client
      def self.jobs
        Jobs.new
      end
    end
  end
end
