# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models::PatternConfigurations
    class PatternOverrideUpdate < T::Struct
      const :token_type, String
      const :push_protection_setting, ::SecretScanning::Models::Settings::BoolSetting

      sig do
        params(params: ActionController::Parameters)
        .returns([
          T.nilable(PatternOverrideUpdate),
          T.nilable(SecretScanning::Errors::ServiceError),
        ])
      end
      def self.from_params(params)
        token_type = params[:token_type]
        unless token_type.is_a?(String) && !token_type.empty?
          return nil, ::SecretScanning::Errors::ServiceError.new("token_type is required")
        end

        input_setting = params[:push_protection_setting]
        push_protection_setting = ::SecretScanning::Models::Settings::BoolSetting.try_deserialize(input_setting)
        if push_protection_setting.nil?
          return nil, ::SecretScanning::Errors::ServiceError.new("push_protection_setting is invalid: #{input_setting}")
        end

        [new(token_type:, push_protection_setting:), nil]
      end

      sig { returns(GitHub::Proto::SecretScanning::Api::V1::PatternOverrideUpdate) }
      def to_proto
        GitHub::Proto::SecretScanning::Api::V1::PatternOverrideUpdate.new(
          token_type:,
          push_protection_setting: push_protection_setting.to_proto,
        )
      end
    end
  end
end
