# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    class PatternConfigsService

      sig do
        params(
          owner: T.any(Organization, Business),
          user: User,
        ).returns([T.nilable(Models::PatternConfigurations::PatternConfiguration), T.nilable(SecretScanning::Errors::ServiceError)])
      end
      def self.get_pattern_config_by_owner(owner, user)
        res = GitHub::TokenScanning::Service::Client.new(user).get_pattern_configuration_by_owner({
          owner: ServiceHelper.to_owner_scope_proto(owner),
          business_id: owner.is_a?(Organization) ? owner.business&.id : nil,
        })

        pattern_config = res&.data&.config
        is_err, err = ServiceHelper.process_response(
          response: res,
          resource_name: "pattern config",
          is_data_valid: pattern_config.present?,
          is_404_ok: false,
          failbot_attributes: {
            "owner.id": owner.id,
            "owner.class": owner.class.name,
            "user.id": user.id,
          },
        )
        return nil, err if is_err || pattern_config.nil?

        [Models::PatternConfigurations::PatternConfiguration.from_proto(pattern_config), nil]
      end

      sig do
        params(
          owner: T.any(Organization, Business),
          user: User,
          number: Integer,
          row_version: T.nilable(String),
          pattern_settings: T::Array[Models::PatternConfigurations::PatternOverrideUpdate],
        ).returns([T.nilable(String), T.nilable(SecretScanning::Errors::ServiceError)])
      end
      def self.upsert_pattern_config(owner:, user:, number:, row_version:, pattern_settings:)
        res = GitHub::TokenScanning::Service::Client.new(user).upsert_pattern_configuration({
          owner: ServiceHelper.to_owner_scope_proto(owner),
          number:,
          row_version:,
          updated_by: user.id,
          pattern_overrides: pattern_settings.map do |setting|
            setting.to_proto
          end,
        })

        row_version = res&.data&.config&.row_version
        is_err, err = ServiceHelper.process_response(
          response: res,
          resource_name: "pattern config",
          is_data_valid: row_version.present?,
          is_404_ok: false,
          failbot_attributes: {
            "owner.id": owner.id,
            "owner.class": owner.class.name,
            "user.id": user.id,
          },
        )
        return nil, err if is_err || row_version.nil?
        [row_version, nil]
      end

      sig do
        params(
          owner: T.any(Organization, Business),
          user: User,
        ).returns([T.nilable(Integer), T.nilable(SecretScanning::Errors::ServiceError)])
      end
      def self.get_enabled_patterns_count(owner, user)
        res = GitHub::TokenScanning::Service::Client.new(user).get_enabled_patterns_count(
          GitHub::Proto::SecretScanning::Api::V1::GetEnabledPatternCountRequest.new(
            owner: ServiceHelper.to_owner_scope_proto(owner),
            business_id: owner.is_a?(Organization) ? owner.business&.id : nil
          )
        )
        patterns_count = res&.data&.enabled_pattern_count
        is_err, err = ServiceHelper.process_response(
          response: res,
          resource_name: "enabled patterns count",
          is_data_valid: patterns_count.present?,
          is_404_ok: false,
          failbot_attributes: {
            "owner.id": owner.id,
            "owner.class": owner.class.name,
            "user.id": user.id,
          },
        )
        return nil, err if is_err || patterns_count.nil?
        [patterns_count, nil]
      end
    end
  end
end
