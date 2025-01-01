# typed: true
# frozen_string_literal: true

require "test_helper"

class Integration::InstallerRedirectTest < GitHub::TestCase
  context "#should_redirect?" do
    test "returns false when no action specified" do
      integration = create(:integration, setup_url: nil, setup_on_update: false)

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: nil,
      )

      refute_predicate redirect, :should_redirect?
    end

    test "returns true when action is :install and App requires setup" do
      integration = create(:integration, setup_url: "http://example.com", setup_on_update: false)

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :install,
      )

      assert_predicate redirect, :should_redirect?
    end

    test "returns false when action is :install and App does not require setup" do
      integration = create(:integration, setup_url: nil, setup_on_update: false)

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :install,
      )

      refute_predicate redirect, :should_redirect?
    end

    test "returns true when action is :update and App requires setup_on_update" do
      integration = create(:integration, setup_url: "http://example.com", setup_on_update: true)

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :update,
      )

      assert_predicate redirect, :should_redirect?
    end

    test "returns false when action is :update and App does not require setup_on_update" do
      integration = create(:integration, setup_url: "http://example.com", setup_on_update: false)

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :update,
      )

      refute_predicate redirect, :should_redirect?
    end

    test "returns true when action is :install and App can request OAuth on installation" do
      integration = create(
        :integration,
        request_oauth_on_install: true,
        application_callback_urls_attributes: [{ url: "http://example.com" }],
        setup_on_update: false,
      )

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :install,
      )

      assert_predicate redirect, :should_redirect?
    end

    test "returns true when action is :update and App can request OAuth on installation" do
      integration = create(
        :integration,
        request_oauth_on_install: true,
        application_callback_urls_attributes: [{ url: "http://example.com/oauth" }],
        setup_url: "http://example.com/setup",
        setup_on_update: true,
      )

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :update,
      )

      assert_predicate redirect, :should_redirect?
    end

    test "returns true when action is :request and the App can request OAuth on installation" do
      integration = create(
        :integration,
        request_oauth_on_install: true,
        application_callback_urls_attributes: [{ url: "http://example.com" }],
        setup_on_update: false,
      )

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :request,
      )

      assert_predicate redirect, :should_redirect?
    end

    test "returns false when action is :update and App can request OAuth on installation but App does not perform setup on update" do
      integration = create(
        :integration,
        request_oauth_on_install: true,
        application_callback_urls_attributes: [{ url: "http://example.com/oauth" }],
        setup_url: "http://example.com/setup",
        setup_on_update: false,
      )

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :update,
      )

      refute_predicate redirect, :should_redirect?
    end

    test "returns true when action is :request and the App requires setup" do
      integration = create(:integration, setup_url: "http://example.com", setup_on_update: false)

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :request,
      )

      assert_predicate redirect, :should_redirect?
    end

    test "returns false when action is :request and the App does not require setup" do
      integration = create(:integration, setup_url: nil, setup_on_update: false)

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :request,
      )

      refute_predicate redirect, :should_redirect?
    end
  end

  context "#oauth_access" do
    test "can bet set outside of initialization" do
      integration = create(:integration, setup_url: nil, setup_on_update: false)

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :update,
      )

      assert_nil redirect.oauth_access

      oauth_access = create(:oauth_access, application: integration)
      redirect.oauth_access = oauth_access

      assert_equal oauth_access, redirect.oauth_access
    end
  end

  context "#url" do
    test "returns nil when the action is unknown" do
      integration = create(:integration, setup_url: "http://example.com", setup_on_update: false)

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :invalid,
      )

      assert_nil redirect.url
    end

    test "returns the installation ID in the query params when present" do
      # EMUs can't be an installation target
      if GitHub.multi_tenant_enterprise?
        target = create(:organization, login: "installation-target", plan: "bronze")
      else
        target = create(:user, login: "installation-target", plan: "bronze")
      end
      repo = create(:private_repository, :minimal, owner: target)
      integration = create(:integration, setup_url: "http://example.com", setup_on_update: false)
      result = integration.install_on(target, repositories: [repo], installer: target, entry_point: :test_case)
      assert result.success?

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        installation: result.installation,
        action: :install,
      )

      url = URI.parse(redirect.url)
      query = Rack::Utils.parse_nested_query(url.query)

      assert_equal result.installation.id.to_s, query.fetch("installation_id")
    end

    test "returns the redirect URL in the query params when return_to_url is given" do
      integration = create(:integration, setup_url: "http://example.com", setup_on_update: false)

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :install,
        return_to_url: "http://example.com/redirect",
      )

      url = URI.parse(redirect.url)
      query = Rack::Utils.parse_nested_query(url.query)

      # TODO: deprecate redirectURL in favor of redirect_url:
      # https://github.com/github/ecosystem-apps/issues/666
      assert_equal "http://example.com/redirect", query.fetch("redirectUrl")
      assert_equal "http://example.com/redirect", query.fetch("redirect_url")
    end

    test "returns the SHA when referring_sha is given" do
      integration = create(:integration, setup_url: "http://example.com", setup_on_update: false)

      sha = "deadbeef00000000deadbeef"

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :install,
        referring_sha: sha,
      )

      url = URI.parse(redirect.url)
      query = Rack::Utils.parse_nested_query(url.query)

      assert_equal sha, query.fetch("sha")
    end

    test "returns the setup_action :install query param when the action is install" do
      integration = create(:integration, setup_url: "http://example.com", setup_on_update: false)

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :install,
      )

      url = URI.parse(redirect.url)
      query = Rack::Utils.parse_nested_query(url.query)

      assert_equal "install", query.fetch("setup_action")
    end

    test "returns the setup_action :install query param when the action is install and the App can OAuth" do
      integration = create(
        :integration,
        request_oauth_on_install: true,
        application_callback_urls_attributes: [{ url: "http://example.com/oauth" }],
      )

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :install,
      )

      url = URI.parse(redirect.url)
      query = Rack::Utils.parse_nested_query(url.query)

      assert_equal "install", query.fetch("setup_action")
    end

    test "returns the setup_action :update query param when the action is update" do
      integration = create(:integration, setup_url: "http://example.com", setup_on_update: true)

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :update,
      )

      url = URI.parse(redirect.url)
      query = Rack::Utils.parse_nested_query(url.query)

      assert_equal "update", query.fetch("setup_action")
    end

    test "returns the setup_action :request query param when the action is request" do
      integration = create(:integration, setup_url: "http://example.com", setup_on_update: true)

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :request,
      )

      url = URI.parse(redirect.url)
      query = Rack::Utils.parse_nested_query(url.query)

      assert_equal "request", query.fetch("setup_action")
    end

    test "returns the setup_action :update query param when the action is update and the App can OAuth" do
      integration = create(
        :integration,
        request_oauth_on_install: true,
        application_callback_urls_attributes: [{ url: "http://example.com/oauth" }],
        setup_url: "http://example.com/setup",
        setup_on_update: true,
      )

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :update,
      )

      url = URI.parse(redirect.url)
      query = Rack::Utils.parse_nested_query(url.query)

      assert_equal "update", query.fetch("setup_action")
    end

    test "returns the callback URL when the action is :install and the App can request OAuth" do
      integration = create(
        :integration,
        request_oauth_on_install: true,
        application_callback_urls_attributes: [{ url: "http://example.com/oauth" }],
      )

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :install,
      )

      assert redirect.url.start_with?("http://example.com/oauth")
      "should use the callback URL '#{integration.callback_url}' but got '#{redirect.url}'"
    end

    test "returns the callback URL when the action is :update and the App can request OAuth" do
      integration = create(
        :integration,
        request_oauth_on_install: true,
        application_callback_urls_attributes: [{ url: "http://example.com/oauth" }],
        setup_url: "http://example.com/setup",
        setup_on_update: true,
      )

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :update,
      )

      assert redirect.url.start_with?("http://example.com/oauth"),
        "should use the callback URL '#{integration.callback_url}' but got '#{redirect.url}'"
    end

    test "returns the callback URL when the action is :request and the App can request OAuth" do
      integration = create(
        :integration,
        request_oauth_on_install: true,
        application_callback_urls_attributes: [{ url: "http://example.com/oauth" }],
        setup_url: "http://example.com/setup",
        setup_on_update: true,
      )

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :request,
      )

      assert redirect.url.start_with?("http://example.com/oauth"),
        "should use the callback URL '#{integration.callback_url}' but got '#{redirect.url}'"
    end

    test "returns the OAuth access code when provided" do
      user = create(:user)
      integration = create(:integration, setup_url: "http://example.com", setup_on_update: true)
      access = integration.grant(user, entry_point: :test_case)

      redirect = Integration::InstallerRedirect.new(
        integration: integration,
        action: :install,
        oauth_access: access,
      )

      url = URI.parse(redirect.url)
      query = Rack::Utils.parse_nested_query(url.query)

      assert_equal access.code, query.fetch("code")
    end

    context "when setup_state_cookie is present" do
      test "pass back a state param if it's present" do
        state = "123456"
        integration, target, installation = build_integration_installation

        setup_state_cookie = build_setup_state_cookie(
          integration: integration,
          target: target,
          data: { "state" => state },
        )

        redirect = Integration::InstallerRedirect.new(
          integration: integration,
          installation: installation,
          action: :install,
          setup_state_cookie: setup_state_cookie,
        )

        url = URI.parse(redirect.url)
        # the resulting url looks like:
        # "http://example.com?installation_id=7&setup_action=install&state=123456"
        assert_equal "http", url.scheme
        assert_equal "example.com", url.host
        assert_predicate url.path, :empty?

        query_params = Rack::Utils.parse_nested_query(url.query)
        assert_equal state, query_params["state"]
        assert_equal  installation.id.to_s, query_params["installation_id"]
        assert_equal "install", query_params["setup_action"]

        if GitHub.multi_tenant_enterprise?
          assert_equal 4, query_params.length
          assert_equal GitHub.host_name_with_tenant, query_params["github_host"]
        else
          assert_equal 3, query_params.length
        end
      end
    end
  end

  def build_integration_installation
    integration = create(:integration, setup_url: "http://example.com", setup_on_update: true)
    # EMUs can't be an installation target
    target = if GitHub.multi_tenant_enterprise?
      target = create(:organization, login: "installation-target", plan: "bronze")
    else
      target = create(:user, login: "installation-target", plan: "bronze")
    end
    repo = create(:private_repository, :minimal, owner: target)
    result = integration.install_on(target, repositories: [repo], installer: target, entry_point: :test_case)
    assert_predicate result, :success?
    [integration, target, result.installation]
  end

  def build_setup_state_cookie(integration:, target:, data:)
    IntegrationInstallation::SetupStateCookie.new(
      cookie_jar: ActionDispatch::Request.new(Rails.application.env_config.deep_dup).cookie_jar,
      data: data,
      integration_id: integration.global_relay_id,
      target_id: target.id,
    )
  end
end
