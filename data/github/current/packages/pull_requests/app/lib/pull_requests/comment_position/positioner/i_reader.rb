# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      # Batched interface describing the object talking to GitRPC. Allows for testing in isolation before the implementation
      # exists as well as mocking out the calls for faster testing.
      module IReader
        extend T::Helpers

        interface!

        # Request the blob to be loaded for the given diff range.
        sig do
          abstract.params(blob: Blob).void
        end
        def request(blob); end

        # Attempt to read out the resulting [commit_oid, path, line] from the GitRPC request.
        sig do
          abstract.params(blob: Blob).returns([String, T.nilable(String), T.nilable(Integer)])
        end
        def fetch(blob); end

        # Perform the batched execution of loading GitRPC data.
        sig { abstract.params(max_attempts: Integer).void }
        def call(max_attempts:); end
      end
    end
  end
end
