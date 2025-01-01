# typed: true
# frozen_string_literal: true

require "test_helper"

class ImportAdvancedSecurityAppPublicKeysJobTest < GitHub::TestCase
  fixtures do
    on_multi_tenant_enterprise do
      make_trusted_oauth_apps_owner
      @app_alias = :code_scanning
      @integration = create(:code_scanning_integration)
    end
  end

  setup do
    on_multi_tenant_enterprise
    @job_klass = ImportAdvancedSecurityAppPublicKeysJob
  end

  context "#perform" do
    test "imports the current public key into the app" do
      assert_empty @integration.public_keys

      # The key should be imported.
      public_key = OpenSSL::PKey::RSA.new(2048).public_key
      stub_env("APP_PUBLIC_KEY_CODE_SCANNING", public_key.to_pem) do
        @job_klass.perform_now
      end

      assert_equal 1, @integration.public_keys.count

      # If the key does not change, it should not be imported again.
      stub_env("APP_PUBLIC_KEY_CODE_SCANNING", public_key.to_pem) do
        @job_klass.perform_now
      end

      assert_equal 1, @integration.public_keys.count

      # If the key changes, it should be imported again.
      public_key = OpenSSL::PKey::RSA.new(2048).public_key
      stub_env("APP_PUBLIC_KEY_CODE_SCANNING", public_key.to_pem) do
        @job_klass.perform_now
      end

      assert_equal 2, @integration.public_keys.count
    end

    test "does not fail if the environment variable is not set" do
      assert_empty @integration.public_keys
      @job_klass.perform_now
      assert_empty @integration.public_keys
    end

    test "does not fail if the integration does not exist" do
      @integration.destroy!
      @job_klass.perform_now
    end
  end

  private def stub_env(key, value)
    old_value = ENV[key]
    ENV[key] = value
    yield if block_given?
  ensure
    ENV[key] = old_value
  end
end
