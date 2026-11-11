# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class AgentAssignments < Platform::Loader
      sig do
        params(
          repository_id: Integer,
          viewer: T.nilable(User),
          issue_id: Integer
        ).returns(Promise[T.nilable(T::Array[::AgentAssignment])])
      end
      def self.load(repository_id, viewer, issue_id)
        self.for(repository_id, viewer).load(issue_id)
      end

      sig { params(repository_id: Integer, viewer: T.nilable(User)).void }
      def initialize(repository_id, viewer)
        @viewer = viewer
        @repository_id = repository_id
      end

      sig do
        params(
          issue_ids: T::Array[Integer]
        ).returns(T::Hash[Integer, T::Array[::AgentAssignment]])
      end
      def fetch(issue_ids)
        assignments = ::AgentAssignment.where(
          repository_id: @repository_id,
          source_type: :issue,
          source_id: issue_ids
        ).order(id: :desc)

        assignments.group_by(&:source_id).transform_values do |issue_assignments|
          issue_assignments.uniq(&:assignee_id)
        end
      end
    end
  end
end
