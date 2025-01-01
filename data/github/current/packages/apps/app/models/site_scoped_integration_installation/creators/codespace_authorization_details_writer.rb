# typed: strict
# frozen_string_literal: true

class SiteScopedIntegrationInstallation
  module Creators
    module CodespaceAuthorizationDetailsWriter
      extend T::Sig
      extend T::Helpers

      requires_ancestor { Kernel }
      requires_ancestor { ScopedIntegrationInstallation::PermissionRowsGenerator }

      SPAN_NAME = "CodespaceAuthorizationDetailsWriter"

      # Transforms a hash with targets as keys and permission rows as values into a
      # serialized authorization details hash.
      sig do
        params(
          permission_rows_per_target: T::Hash[
            ScopedIntegrationInstallation::PermissionRowsGenerator::InstallationTarget,
            T::Array[ScopedIntegrationInstallation::PermissionRowsGenerator::PermissionRow]]
        ).returns(
          T::Hash[String, T.untyped]
        )
      end
      def synthesize_authorization_details!(permission_rows_per_target)
        details = ScopedInstallations::AuthorizationDetails::Builder.build(version: authorization_details_version)

        GitHub.tracer.in_span(SPAN_NAME + ".synthesize_authorization_details", kind: :internal) do |span|
          span.set_attribute("gh.authorization_details_version", details.version)

          permission_rows_per_target.each do |_target, permission_rows|
            permissions_by_subject = permission_rows_to_permissions_by_subject(permission_rows)

            permissions_by_subject.each do |subject, permissions|
              resource_type, subject_id, selection_type = subject.split(":")
              resource_type = resource_type_for!(resource_type)
              selection =
                if selection_type == "all"
                  ScopedInstallations::AuthorizationDetails::Selection::All
                else
                  [subject_id.to_i]
                end

              details.add_permissions_selection(resource_type:, permissions:, selection:)
            end
          end
        end

        details.validate!
        details.serialize
      end

      sig { params(e: String).void }
      def raise_error(e)
        raise ScopedIntegrationInstallation::Result::Error, e
      end

      sig { params(err: StandardError).void }
      def log_permissions_error_details(err)
        GitHub.logger.warn( # Other details about the codespaces are logged at a higher level.
          "gh.codespace_ssii_creator_error" => err.class.name,
          "gh.codespace_ssii_creator_error_origin" => self.class.name,
          "gh.codespace_ssii_creator_error_details" => err.message,
        )
      end

      sig { params(e: StandardError).returns(String) }
      def error_message_for_exception(e)
        case e
        when ActiveRecord::ActiveRecordError, JSON::Schema::ValidationError, KeyError
          "There was a problem while granting permissions"
        when ScopedIntegrationInstallation::Result::Error
          e.message
        else
          "An unexpected error occurred"
        end
      end

      sig do
        params(resource_name: String)
        .returns(::ScopedInstallations::AuthorizationDetails::ResourceType)
      end
      def resource_type_for!(resource_name)
        ::ScopedInstallations::AuthorizationDetails::ResourceType.for(resource_name)
      end

      sig { returns(Integer) }
      def authorization_details_version
        GitHub.flipper[:use_authorization_details_v2_on_codespaces].enabled? ? 2 : 1
      end
    end
  end
end
