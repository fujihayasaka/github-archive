# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module PullRequest
      class CommentPositions < Platform::Loader
        def self.load(pull_request, review_thread)
          self.for(pull_request).load(review_thread)
        end

        def initialize(pull_request)
          @pull_request = pull_request
        end

        private

        def fetch(review_threads)
          PullRequests::CommentPosition::Legacy::Conversion.for_threads(
            pull_request: @pull_request,
            threads: review_threads
          )
        end
      end
    end
  end
end
