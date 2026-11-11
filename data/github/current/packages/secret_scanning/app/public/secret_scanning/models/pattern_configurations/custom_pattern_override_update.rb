# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models::PatternConfigurations
    class CustomPatternOverrideUpdate < T::Struct
      const :token_type, String
      const :row_version, String
      const :push_protection_setting, ::SecretScanning::Models::Settings::BoolSetting

      sig do
        params(params: T.any(ActionController::Parameters, T::Hash[T.untyped, T.untyped]))
        .returns([
          T.nilable(CustomPatternOverrideUpdate),
          T.nilable(SecretScanning::Errors::ServiceError),
        ])
      end
      def self.from_params_ui(params)
        token_type = params[:token_type] || params["token_type"]
        unless token_type.is_a?(String) && !token_type.empty?
          return nil, ::SecretScanning::Errors::ServiceError.new("token_type is required")
        end

        row_version = params[:row_version] || params["row_version"]
        unless row_version.is_a?(String) && !row_version.empty?
          return nil, ::SecretScanning::Errors::ServiceError.new("row_version is required")
        end

        input_setting = params[:push_protection_setting] || params["push_protection_setting"]
        push_protection_setting = ::SecretScanning::Models::Settings::BoolSetting.try_deserialize(input_setting)
        if push_protection_setting.nil?
          return nil, ::SecretScanning::Errors::ServiceError.new("push_protection_setting is invalid: #{input_setting}")
        end

        [new(token_type:, push_protection_setting:, row_version:), nil]
      end

      sig do
        params(params: T.any(ActionController::Parameters, T::Hash[T.untyped, T.untyped]))
        .returns([
          T.nilable(CustomPatternOverrideUpdate),
          T.nilable(SecretScanning::Errors::ServiceError),
        ])
      end
      def self.from_params_api(params)
        token_type = params[:token_type] || params["token_type"]
        unless token_type.is_a?(String) && !token_type.empty?
          return nil, ::SecretScanning::Errors::ServiceError.new("token_type is required")
        end

        row_version = params[:custom_pattern_version] || params["custom_pattern_version"]
        unless row_version.is_a?(String) && !row_version.empty?
          return nil, ::SecretScanning::Errors::ServiceError.new("custom_pattern_version is required")
        end

        input_setting = params[:push_protection_setting] || params["push_protection_setting"]
        push_protection_setting = ::SecretScanning::Models::Settings::BoolSetting.try_deserialize(input_setting)
        if push_protection_setting.nil?
          return nil, ::SecretScanning::Errors::ServiceError.new("push_protection_setting is invalid: #{input_setting}")
        end

        [new(token_type:, push_protection_setting:, row_version:), nil]
      end

      sig { returns(GitHub::Proto::SecretScanning::Api::V1::CustomPatternOverrideUpdate) }
      def to_proto
        GitHub::Proto::SecretScanning::Api::V1::CustomPatternOverrideUpdate.new(
          token_type:,
          row_version:,
          push_protection_setting: push_protection_setting.to_proto,
        )
      end
    end
  end
end
