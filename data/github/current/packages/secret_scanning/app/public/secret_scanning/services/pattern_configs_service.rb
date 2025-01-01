# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    class PatternConfigsService

      sig do
        params(
          owner: T.any(Organization, Business),
          user: User,
        ).returns([T.nilable(Models::PatternConfigurations::PatternConfiguration), T.nilable(StandardError)])
      end
      def self.get_pattern_config_by_owner(owner, user)
        res = GitHub::TokenScanning::Service::Client.new(user).get_pattern_configuration_by_owner({
          owner: ServiceHelper.to_owner_scope_proto(owner),
          business_id: owner.is_a?(Organization) ? owner.business&.id : nil,
        })

        pattern_config = res&.data&.config
        is_err, err = ServiceHelper.process_response(
          response: res,
          operation: "fetching pattern config",
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
          row_version: T.nilable(String),
          provider_pattern_settings: T::Array[Models::PatternConfigurations::PatternOverrideUpdate],
          custom_pattern_settings: T::Array[Models::PatternConfigurations::CustomPatternOverrideUpdate],
        ).returns([T.nilable(String), T.nilable(Integer), T.nilable(StandardError)])
      end
      def self.upsert_pattern_config(owner:, user:, row_version:, provider_pattern_settings:, custom_pattern_settings:)
        req = {
          owner: ServiceHelper.to_owner_scope_proto(owner),
          row_version:,
          updated_by: user.id,
          updated_by_login: user.display_login,
          pattern_overrides: provider_pattern_settings.map do |setting|
            setting.to_proto
          end,
          custom_pattern_overrides: custom_pattern_settings.map do |setting|
            setting.to_proto
          end,
        }
        if owner.is_a?(Organization) && owner.business
          req[:business] = ServiceHelper.to_owner_scope_proto(T.must(owner.business))
        end
        res = GitHub::TokenScanning::Service::Client.new(user).upsert_pattern_configuration(req)
        row_version = res&.data&.config&.row_version
        number = res&.data&.config&.number
        is_err, err = ServiceHelper.process_response(
          response: res,
          operation: "upserting pattern config",
          is_data_valid: row_version.present? && number.present?,
          is_404_ok: false,
          failbot_attributes: {
            "owner.id": owner.id,
            "owner.class": owner.class.name,
            "user.id": user.id,
          },
        )
        return nil, nil, err if is_err || row_version.nil? || number.nil?
        [row_version, number, nil]
      end

      sig do
        params(
          owner: T.any(Organization, Business),
          user: User,
        ).returns([T.nilable(Integer), T.nilable(StandardError)])
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
          operation: "fetching enabled patterns count",
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
