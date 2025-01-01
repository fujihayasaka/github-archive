# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module Structs
      module V2::ResourceSelection
        extend T::Sig
        extend T::Helpers

        interface!

        requires_ancestor { Kernel }

        sig { abstract.params(name: String).returns(T.nilable(Permission::Action)) }
        def granted_access_on_all_subjects(name); end

        sig do
          abstract.params(
            name: String,
            subject_ids: T::Array[Integer]
          ).returns(PublicMethods::SubjectIdActionPairs)
        end
        def granted_subject_ids_with_actions_for(name, subject_ids); end

        sig { abstract.returns(T.any(Selection, T::Array[Integer])) }
        def selection; end

        sig { abstract.returns(T::Hash[String, T.untyped]) }
        def permissions; end

        sig { abstract.returns(T::Hash[String, T.untyped]) }
        def serialize; end

        sig do
          abstract.params(
            permissions: T::Hash[String, Symbol],
            selection: T.any(Selection, T::Array[Integer])
          ).void
        end
        def add_permissions_selection(permissions:, selection:); end
      end
    end
  end
end
