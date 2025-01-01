# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module CopilotWorkbench
      attr_accessor :copilot_workbench_aca_management_token
      attr_accessor :copilot_workbench_aca_deployment_token
      attr_accessor :copilot_workbench_aca_database_token
      attr_accessor :copilot_workbench_aca_jwt_private_key
      attr_accessor :copilot_workbench_snapshot_storage_account
      attr_accessor :copilot_workbench_scanning_storage_account
      attr_accessor :copilot_workbench_spn_client_secret
      attr_accessor :copilot_workbench_spn_client_id
      attr_accessor :copilot_workbench_spn_tenant_id

      def spark_simple_box_key
        @spark_simple_box_key ||= T.let(ENV["SPARK_SIMPLE_BOX_KEY"], T.nilable(String))
      end

      def spark_simple_box_key=(key = nil)
        @spark_simple_box_key = T.let(key, T.nilable(String))
      end

      def spark_simple_box
        RbNaCl::SimpleBox.from_secret_key(spark_simple_box_key.b) unless spark_simple_box_key.nil?
      end

      def encrypt_spark_token(token)
        return if token.nil?

        Kernel.raise RuntimeError.new("spark_simple_box_key not set") if spark_simple_box_key.nil?

        encrypted = spark_simple_box.encrypt(token)
        Base64.urlsafe_encode64(encrypted)
      end

      def decrypt_spark_token(token)
        return if token.nil?

        Kernel.raise RuntimeError.new("spark_simple_box_key not set") if spark_simple_box_key.nil?

        decoded = Base64.urlsafe_decode64(token)
        spark_simple_box.decrypt(decoded)
      end
    end
  end
  extend Config::CopilotWorkbench
end
