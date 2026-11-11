# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class PinnedIssueFields < Platform::Loader
      sig { params(issue_type: IssueType, owner: Organization, viewer: T.nilable(User), repository_id: T.nilable(Integer)).returns(Promise[T::Array[Issues::IIssueField]]) }
      def self.load(issue_type:, owner:, viewer: nil, repository_id: nil)
        self.for(viewer, repository_id).load([issue_type, owner])
      end

      sig { params(viewer: T.nilable(User), repository_id: T.nilable(Integer)).void }
      def initialize(viewer = nil, repository_id = nil)
        @viewer = viewer
        @repository_id = repository_id
      end

      sig { params(inputs: T::Array[[IssueType, Organization]]).returns(T::Hash[[IssueType, Organization], T::Array[Issues::IIssueField]]) }
      def fetch(inputs)
        results = Issues.domain.issue_fields.get_pinned_fields_for_issue_types(
          inputs: inputs,
          viewer: @viewer,
          repository_id: @repository_id,
        )

        if @repository_id
          results = results.transform_values do |fields|
            fields.map { |field| Platform::Models::IssueFieldWithRepoContext.new(field, repository_id: @repository_id) }
          end
        end

        T.cast(results, T::Hash[[IssueType, Organization], T::Array[Issues::IIssueField]])
      end
    end
  end
end
