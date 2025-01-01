# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module PublicMethods
      extend T::Helpers

      abstract!

      AUTHZD_NAMESPACE = "authorization_details"
      SCHEMA_FILE_PATH = "packages/apps/app/models/scoped_installations/authorization_details/schemas/v%s.json"

      SubjectIds = T.type_alias do
        T::Array[Integer]
      end

      SubjectIdActionPairs = T.type_alias do
        T::Array[[Integer, Integer]]
      end

      sig { abstract.returns(T::Hash[String, Symbol]) }
      def all_permissions; end

      sig { params(resource_type: ResourceType, name: T.nilable(T.any(String, Symbol)), min_action: Symbol).returns(T::Boolean) }
      def granted_access_on_all_subjects?(resource_type, name, min_action: :read)
        if name.present?
          name = name.to_s

          action = granted_access_on_all_subjects(resource_type, name)
          action.present? ? action >= T.must(Permission.actions[min_action]) : false
        else
          subject_types(resource_type).any? { |name| granted_access_on_all_subjects?(resource_type, name, min_action:) }
        end
      end

      sig { abstract.params(resource_type: ResourceType, name: String).returns(T.nilable(Integer)) }
      def granted_access_on_all_subjects(resource_type, name); end

      sig { abstract.params(package: PackageRegistry::PackageSubject).void }
      def remove_package_permission(package); end

      sig do
        abstract.params(
          resource_type: ResourceType,
          permissions: T::Hash[String, Symbol],
          selection: T.any(Selection, T::Array[Integer])
        ).void
      end
      def add_permissions_selection(resource_type:, permissions:, selection:); end

      sig do
        abstract.params(
          resource_type: ResourceType,
          selection: T.any(Selection, T::Array[Integer]),
          resource: String,
          action: T.any(Symbol, Permission::Action)
        ).returns(T::Boolean)
      end
      def explicitly_grants_permission?(resource_type:, selection:, resource:, action: :read); end

      sig { abstract.returns(T::Hash[String, T.untyped]) }
      def serialize; end

      sig { abstract.returns(Integer) }
      def version; end

      sig { void }
      def validate!
        path_for_version = SCHEMA_FILE_PATH % version
        schema_file_path = Rails.root.join(*(path_for_version.split("/"))).to_s
        JSON::Validator.validate!(schema_file_path, self.serialize.to_json)
      end

      sig do
        abstract.params(
          resource_type: ResourceType,
          name: String,
          subject_ids: T::Array[Integer]
        ).returns(SubjectIdActionPairs)
      end
      def granted_subject_ids_with_actions_for(resource_type, name, subject_ids); end

      sig { abstract.params(resource_type: ResourceType).returns(Selection) }
      def selection_for(resource_type); end

      sig { abstract.params(resource_type: ResourceType).returns(T::Array[String]) }
      def subject_types(resource_type); end

      sig { abstract.params(resource_type: ResourceType, name: T.nilable(String), min_action: Symbol).returns(T::Array[Integer]) }
      def granted_subject_ids_for(resource_type, name = nil, min_action: :read); end

      sig { abstract.returns(T::Array[Authzd::Proto::Attribute]) }
      def authzd_proto_attributes; end

      sig { overridable.returns(String) }
      def authzd_namespace; AUTHZD_NAMESPACE; end
    end
  end
end
