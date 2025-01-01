# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    class ServiceHelper
      include ::SecretScanning::Constants

      # This takes a response from TSS, logs any errors found,
      # and returns a result tuple.
      # The first field is true if an error was encountered.
      # The second field (if the first was true) is potentially an error; will be nil error if response is 404
      sig do
        type_parameters(:U).params(
          response: T.nilable(Twirp::ClientResp[
            T.all(
              T.type_parameter(:U),
              Kernel, # Let's us call #nil? on a generic
            )
          ]),
          # Name that will appear in error logs
          resource_name: String,
          # Additional validation of underlying data that caller performs and provides to this
          # function because this won't have access to underlying data of an unconstrained generic.
          # Defaults to true, which means data validation will defer to the general
          # error, nil, etc. checks on the response instead of underlying data.
          is_data_valid: T::Boolean,
          # True if 404 is an expected error, false if not so that error gets logged. Defaults to true.
          is_404_ok: T::Boolean,
          failbot_attributes: T::Hash[Symbol, T.untyped],
        ).returns([T::Boolean, T.nilable(SecretScanning::Errors::ServiceError)])
      end
      def self.process_response(response:, resource_name:, is_data_valid: true, is_404_ok: true, failbot_attributes: {})
        if response.nil?
          service_error = SecretScanning::Errors::ServiceError.new("An unknown error has occurred while fetching #{resource_name}")
          Failbot.report(service_error, app: FAILBOT_APP_NAME, **failbot_attributes)
          return true, service_error
        end

        error = response.error
        if error.present?
          if error.code == :failed_precondition && error.msg.include?("row_version")
            return true, nil
          end

          if error.code == :not_found
            if is_404_ok
              return true, nil
            else
              service_error = SecretScanning::Errors::ServiceError.new("An unexpected 404 occurred while fetching #{resource_name}")
              Failbot.report(service_error, app: FAILBOT_APP_NAME, **failbot_attributes)
              return true, service_error
            end
          end

          service_error = SecretScanning::Errors::ServiceError.new("Received error from TSS: #{error.msg}")
          Failbot.report(service_error, app: FAILBOT_APP_NAME, **failbot_attributes)
          return true, service_error
        end

        if response.data.nil? || !is_data_valid
          service_error = SecretScanning::Errors::ServiceError.new("An error has occurred while fetching #{resource_name}")
          Failbot.report(service_error, app: FAILBOT_APP_NAME, **failbot_attributes)
          return true, service_error
        end

        [false, nil]
      end

      sig do
        params(
          target: T.any(User, Repository, Organization, Business),
        ).returns(GitHub::Proto::SecretScanning::Types::V1::Owner)
      end
      def self.to_owner_scope_proto(target)
        case target
        when Repository
          GitHub::Proto::SecretScanning::Types::V1::Owner.new(
            id: target.id,
            owner_scope: GitHub::Proto::SecretScanning::Types::V1::OwnerScope::REPOSITORY_SCOPE,
          )
        when Organization
          GitHub::Proto::SecretScanning::Types::V1::Owner.new(
            id: target.id,
            owner_scope: GitHub::Proto::SecretScanning::Types::V1::OwnerScope::ORGANIZATION_SCOPE,
          )
        when Business
          GitHub::Proto::SecretScanning::Types::V1::Owner.new(
            id: target.id,
            owner_scope: GitHub::Proto::SecretScanning::Types::V1::OwnerScope::BUSINESS_SCOPE,
          )
        when User
          GitHub::Proto::SecretScanning::Types::V1::Owner.new(
            id: target.id,
            owner_scope: GitHub::Proto::SecretScanning::Types::V1::OwnerScope::USER_SCOPE,
          )
        else
          T.absurd(target)
        end
      end
    end
  end
end
