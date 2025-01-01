# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    class Serializer
      extend T::Sig

      SCHEMA_FILE_PATH = "packages/apps/app/models/scoped_installations/authorization_details/schemas/v1.json"
      VERSION = 1

      sig do
        params(attributes: T::Hash[Symbol, T.untyped]).returns(
          T.any(
            [T::Hash[Symbol, T.untyped], NilClass],
            [NilClass, String]
         ))
      end
      def self.generate(attributes = {})
        GitHub.tracer.in_span("ScopedInstallations::AuthorizationDetails::Serialize.generate", kind: :internal) do
          GitHub.dogstats.distribution_time("scoped_installations.authorization_details.serializer.generate.latency") do
            target = attributes[:target]
            permissions = attributes[:permissions] || {}
            repository_selection = attributes[:repository_selection] || Selection::None
            repository_ids = attributes[:repository_ids] || []

            details = new(
              target: target,
              permissions: permissions,
              repository_selection: repository_selection,
              repository_ids: repository_ids
            ).generate

            valid, error_message = validate(details)
            return [nil, error_message] unless valid

            [details, nil]
          end
        end
      end

      sig do
        params(hash: T::Hash[T.untyped, T.untyped]).returns(
          T.any(
            [TrueClass, NilClass],
            [FalseClass, String]
          )
        )
      end
      def self.validate(hash)
        GitHub.tracer.in_span("ScopedInstallations::AuthorizationDetails::Serialize.validate", kind: :internal) do
          begin
            schema_file_path = Rails.root.join(*(SCHEMA_FILE_PATH.split("/"))).to_s
            JSON::Validator.validate!(schema_file_path, hash.to_json)

            [true, nil]
          rescue JSON::Schema::ValidationError => e
            [false, e.message]
          end
        end
      end

      sig do
        params(
          target: T.any(Organization, User, Business, NilClass),
          permissions: T::Hash[String, Symbol],
          repository_selection: Selection,
          repository_ids: T::Array[Integer]
        ).void
      end
      def initialize(target:, permissions:, repository_selection:, repository_ids:)
        @target = target
        @permissions = permissions
        @repository_selection = repository_selection
        @repository_ids = repository_ids
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def generate
        GitHub.tracer.in_span("ScopedInstallations::AuthorizationDetails::Serialize#generate", kind: :internal) do
          struct = Structs::V1.new

          repo_permissions = Repository::Resources.filter(@permissions)

          if !@repository_selection.none? && repo_permissions.any?
            resource_type = ResourceType::Repository

            struct.set_selection_for(resource_type, @repository_selection)
            struct.set_subject_types_and_actions_for(resource_type, repo_permissions)

            if @repository_selection.subset? && @repository_ids.present?
              struct.set_subject_ids_for(resource_type, @repository_ids)
            end
          end

          if @target.is_a?(Organization)
            org_permissions = Organization::Resources.filter(@permissions)

            if org_permissions.any?
              resource_type = ResourceType::Organization

              struct.set_selection_for(resource_type, Selection::Subset)
              struct.set_subject_ids_for(resource_type, [T.must(@target.id)])
              struct.set_subject_types_and_actions_for(resource_type, org_permissions)
            end
          end

          struct.serialize
        end
      end
    end
  end
end
