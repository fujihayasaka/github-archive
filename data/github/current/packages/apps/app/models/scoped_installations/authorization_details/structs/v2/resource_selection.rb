# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module Structs
      module V2::ResourceSelection
        extend T::Helpers

        abstract!

        requires_ancestor { Kernel }

        sig { abstract.params(name: String).returns(T.nilable(Permission::Action)) }
        def granted_access_on_all_subjects(name); end

        # Broader ID type for internal selection methods that may return string IDs (stores).
        SubjectIdActionPairs = T.type_alias { T::Array[[T.any(Integer, String), Integer]] }

        sig do
          abstract.params(
            name: String,
            subject_ids: T.nilable(T::Array[T.any(Integer, String)])
          ).returns(SubjectIdActionPairs)
        end
        def granted_subject_ids_with_actions_for(name, subject_ids); end

        sig { params(name: String, min_action: Permission::Action).returns(T::Array[T.any(Integer, String)]) }
        def granted_subject_ids_for(name, min_action:)
          min_action = min_action.serialize

          granted_subject_ids_with_actions_for(name, nil).filter_map do |subject_id, action|
            subject_id if action >= min_action
          end
        end

        sig { abstract.returns(T.any(Selection, T::Array[T.any(Integer, String)])) }
        def selection; end

        sig { abstract.returns(T::Hash[String, T.untyped]) }
        def permissions; end

        sig { abstract.returns(T::Hash[String, T.untyped]) }
        def serialize; end

        sig do
          abstract.params(
            permissions: T::Hash[String, Symbol],
            selection: T.any(Selection, T::Array[T.any(Integer, String)])
          ).void
        end
        def add_permissions_selection(permissions:, selection:); end

        sig { abstract.returns(T::Array[Authzd::Proto::Attribute]) }
        def authzd_proto_attributes; end
      end
    end
  end
end
