# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    # Routes pull-request-related content state change topics to the ContentChangesPullRequest stream processor key.
    # All processing logic is inherited from ContentStateChange.
    class ContentStateChangePullRequest < ContentStateChange
      sig { override.returns(StreamProcessorKey) }
      def self.stream_processor_key
        StreamProcessorKey::ContentChangesPullRequest
      end

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.PullRequestClose\Z/,
          /github\.v1\.PullRequestReopen\Z/,
          /github\.v1\.PullRequestMerge\Z/,
          /github\.v1\.PullRequestConvertToDraft\Z/,
          /github\.v1\.PullRequestReadyForReview\Z/,
        ]
      end
    end
  end
end
