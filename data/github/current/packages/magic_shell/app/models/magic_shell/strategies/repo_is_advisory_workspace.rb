# typed: strict
# frozen_string_literal: true

class MagicShell
  module Strategies
    class RepoIsAdvisoryWorkspace < Base::RepositoryContext
      DataType = T.type_alias { T::Boolean }
      DataTypeValue = type_member { { fixed: T.nilable(DataType) } }

      sig { override.returns(T::Types::Base) }
      def self.data_type
        T::Utils.coerce(DataType)
      end

      # TODO: It's not entirely clear what to do here. Is it safe to default to a `false` response if the live data isn't available? Would it be
      # better to raise?
      sig { override.returns(DataTypeValue) }
      def gracefully_degraded_data
        false
      end

      sig { override.params(viewer: T.nilable(::User), repository: T.nilable(::Repository)).returns(T::Boolean) }
      def can_use_precomputed_data?(viewer, repository)
        true
      end

      sig { override.params(viewer: T.nilable(::User), repository: T.nilable(::Repository)).returns(DataTypeValue) }
      def fetch_live_data(viewer, repository)
        repository = T.must_because(repository) { "Repository will always be provided in repo context queries" }
        repository.advisory_workspace?
      end

      sig { override.params(repository: T.nilable(::Repository)).returns(DataTypeValue) }
      def precomputed(repository)
        fetch_live_data(nil, repository)
      end
    end
  end
end
