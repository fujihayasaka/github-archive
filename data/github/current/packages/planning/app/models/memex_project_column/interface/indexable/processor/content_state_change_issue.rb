# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    # Routes issue-related content state change topics to the ContentChangesIssue stream processor key.
    # All processing logic is inherited from ContentStateChange.
    class ContentStateChangeIssue < ContentStateChange
      sig { override.returns(StreamProcessorKey) }
      def self.stream_processor_key
        StreamProcessorKey::ContentChangesIssue
      end

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.IssueClose\Z/,
          /github\.v1\.IssueReopen\Z/,
          /github\.v1\.IssueConvertedToDiscussion\Z/,
        ]
      end
    end
  end
end
