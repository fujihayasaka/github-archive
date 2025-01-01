# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module Structs
      class V2 < T::Struct
        extend T::Sig

        include PublicMethods
        include AccessorsDependency
        include GrantableDependency
        include SerializationDependency

        prop :version, Integer, default: 2

        prop :codespace, T.nilable(SelectionWithPermissions)
        prop :organization, T.nilable(SelectionWithPermissions)

        prop :package, T.nilable(SubjectIdsOnlySelection)
        prop :pull_request, T.nilable(SubjectIdsOnlySelection)
        prop :workflow_run, T.nilable(SubjectIdsOnlySelection)

        prop :repository, T.nilable(T.any(SelectionWithPermissions, ElevatedAccessSelection))
      end
    end
  end
end
