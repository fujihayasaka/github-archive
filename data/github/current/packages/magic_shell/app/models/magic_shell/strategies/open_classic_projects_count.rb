# typed: strict
# frozen_string_literal: true
class MagicShell
  module Strategies
    class OpenClassicProjectsCount < Base::RepositoryContext

      extend T::Sig

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
        true
      end

      sig { override.params(viewer: T.nilable(::User), repository: T.nilable(::Repository)).returns(DataTypeValue) }
      def fetch_live_data(viewer, repository)
        repository = T.must_because(repository) { "Repository will always be provided in repo context queries" }
        repository.projects.open_projects.count
      end

      sig { override.params(repository: T.nilable(::Repository)).returns(DataTypeValue) }
      def precomputed(repository)
        fetch_live_data(nil, repository)
      end
    end
  end
end
