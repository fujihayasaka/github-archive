# typed: true
# frozen_string_literal: true

require "test_helper"

class TenantScopedUrlTest < GitHub::TestCase

  fixtures do
    @app = create(:integration)
    @syncable_first_party_app =
      if GitHub.multi_tenant_enterprise?
        create(:github_owned_integration)
      else
        create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true })
      end
  end

  context ".app_supports_tenant_url?" do
    test "is false for regular integrations" do
      refute ::ProximaAppRequest::TenantScopedUrl.app_supports_tenant_url?(@app)
    end

    if GitHub.multi_tenant_enterprise?
      test "is true for first-party integrations" do
        assert ::ProximaAppRequest::TenantScopedUrl.app_supports_tenant_url?(@syncable_first_party_app)
      end

      test "is false for third-party integrations" do
        third_party_app = create(:integration, owner: make_proxima_third_party_apps_owner)
        refute ::ProximaAppRequest::TenantScopedUrl.app_supports_tenant_url?(third_party_app)
      end

      test "is false for other integrations" do
        refute ::ProximaAppRequest::TenantScopedUrl.app_supports_tenant_url?(@app)
      end
    else
      test "is true for internal integrations available on multi-tenant environments" do
        assert ::ProximaAppRequest::TenantScopedUrl.app_supports_tenant_url?(@syncable_first_party_app)
      end

      test "is false for internal integrations unavailable on multi-tenant environments" do
        dotcom_only_first_party_app = build(:github_owned_integration, proxima_availability: :unavailable)
        refute ::ProximaAppRequest::TenantScopedUrl.app_supports_tenant_url?(dotcom_only_first_party_app)
      end

      test "is false for third-party integrations available on multi-tenant environments" do
        syncable_third_party_app = create(
          :integration,
          owner: make_proxima_third_party_apps_owner,
          proxima_availability: :available
        )

        refute ::ProximaAppRequest::TenantScopedUrl.app_supports_tenant_url?(syncable_third_party_app)
      end
    end
  end

  context ".should_generate?" do
    test "returns false when URL is nil" do
      assert_equal false, ::ProximaAppRequest::TenantScopedUrl.should_generate?(app: @syncable_first_party_app, url: nil)
    end

    test "returns false when URL is empty string" do
      assert_equal false, ::ProximaAppRequest::TenantScopedUrl.should_generate?(app: @syncable_first_party_app, url: "")
    end

    test "returns false when URL does not contain {hostname}" do
      assert_equal false, ::ProximaAppRequest::TenantScopedUrl.should_generate?(app: @syncable_first_party_app, url: "https://example.com/callback")
    end

    test "returns true when URL contains {hostname}" do
      assert_equal true, ::ProximaAppRequest::TenantScopedUrl.should_generate?(app: @syncable_first_party_app, url: "https://{hostname}/callback")
    end

    test "returns false when URL contains {hostname} but app is not first party syncable" do
      assert_equal false, ::ProximaAppRequest::TenantScopedUrl.should_generate?(app: @app, url: "https://{hostname}/callback")
    end
  end

  context ".generate" do
    test "returns expected tenant-scoped URL when multi-tenant enterprise is enabled" do
      GitHub.stubs(:multi_tenant_enterprise?).returns(true)
      GitHub::CurrentTenant.stubs(:get).returns(stub(slug: "tenant-slug"))
      assert_predicate GitHub::CurrentTenant.get.slug, :present?

      expected_url = "https://#{GitHub::host_name_with_tenant}/callback" # Ex: https://tenant-slug.ghe.com
      assert_equal expected_url, ::ProximaAppRequest::TenantScopedUrl.generate("https://{hostname}/callback", @app)
    end

    test "returns expected tenant-scoped URL when multi-tenant enterprise is disabled and app is a dependabot app" do
      app = create(:dependabot_integration)
      enable_feature_flag(:override_generated_url_hostname, app)
      GitHub.stubs(:multi_tenant_enterprise?).returns(false)
      GitHub::CurrentTenant.stubs(:get).returns(stub(slug: "tenant-slug"))

      expected_url = "https://githubapp.com/callback"
      assert_equal expected_url, ::ProximaAppRequest::TenantScopedUrl.generate("https://{hostname}/callback", app)
    end

    test "returns hostname when multi-tenant enterprise is not enabled" do
      GitHub.stubs(:multi_tenant_enterprise?).returns(false)
      assert_equal "https://#{GitHub::host_name}/callback", ::ProximaAppRequest::TenantScopedUrl.generate("https://{hostname}/callback", @app)
    end
  end
end
