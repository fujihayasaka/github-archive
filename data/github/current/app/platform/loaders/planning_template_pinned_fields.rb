# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class PlanningTemplatePinnedFields < Platform::Loader
      sig { params(owner: Organization, viewer: T.nilable(User)).returns(Promise[T::Array[Issues::IIssueField]]) }
      def self.load(owner:, viewer: nil)
        self.for(viewer).load(owner)
      end

      sig { params(viewer: T.nilable(User)).void }
      def initialize(viewer = nil)
        @viewer = viewer
      end

      sig { params(inputs: T::Array[Organization]).returns(T::Hash[Organization, T::Array[Issues::IIssueField]]) }
      def fetch(inputs)
        T.cast(Issues.domain.issue_fields.get_pinned_fields_for_organizations(orgs: inputs, viewer: @viewer), T::Hash[Organization, T::Array[Issues::IIssueField]])
      end
    end
  end
end
