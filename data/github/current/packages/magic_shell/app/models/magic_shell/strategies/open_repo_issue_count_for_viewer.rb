# typed: strict
# frozen_string_literal: true

# This is an example of a strategy that determines if it applies based on both
# the repo context and the viewer context.
#
# But, the denormalized data in the data store should be stored using the
# repository_id, as the denormalized version ignores the viewer context.
# This is still a TODO.
class MagicShell
  module Strategies
    class OpenRepoIssueCountForViewer < Base::RepositoryContext
      DataType = Integer
      DataTypeValue = type_member { { fixed: T.nilable(DataType) } }

      sig { override.returns(T.class_of(DataType)) }
      def self.data_type = DataType

      sig { override.returns(DataTypeValue) }
      def gracefully_degraded_data
        nil
      end

      sig { override.params(viewer: T.nilable(::User), repository: T.nilable(::Repository)).returns(T::Boolean) }
      def can_use_precomputed_data?(viewer, repository)
        return true if viewer.nil?
        return false if repository.nil?

        return false if viewer.spammy?
        return false if repository.owner_id == viewer.id
        return false if viewer.site_admin?

        true
      end

      sig { override.params(viewer: T.nilable(::User), repository: T.nilable(::Repository)).returns(DataTypeValue) }
      def fetch_live_data(viewer, repository)
        T.must(repository).open_issue_count_for(viewer) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      sig { override.params(repository: T.nilable(::Repository)).returns(DataTypeValue) }
      def precomputed(repository)
        fetch_live_data(nil, repository)
      end
    end
  end
end
