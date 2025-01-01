# typed: true
# frozen_string_literal: true

require "test_helper"

class RateLimitKeyTest < GitHub::TestCase
  context "#for" do
    context "Bot" do
      context "with a IntegrationInstallation" do
        test "returns installation:id" do
          integration_installation = make_integration_installation(repository: create(:repository))
          assert_equal "installation-#{integration_installation.id}", RateLimitKey.for(integration_installation.bot)
        end
      end

      context "with a ScopedIntegrationInstallation" do
        test "returns parent:id" do
          repository               = create(:repository)
          integration_installation = make_integration_installation(repository: repository, permissions: { "metadata" => :read })
          scoped_installation      = make_scoped_integration_installation(parent: integration_installation, repositories: [repository])
          assert_equal "installation-#{integration_installation.id}", RateLimitKey.for(scoped_installation.bot)
        end

        test "sets a repository ID in the key for internal Apps with the per-repo rate limit capability scoped to one repository" do
          app = create_privileged_app_with_capabilities(capabilities: { per_repo_rate_limit: true })

          repository               = create(:repository)
          owner                    = repository.owner
          integration_installation = make_integration_installation(integration: app, repository: repository, permissions: { "metadata" => :read })
          scoped_installation      = make_scoped_integration_installation(parent: integration_installation, repositories: [repository])

          assert_equal "installation-#{integration_installation.id}-#{repository.id}", RateLimitKey.for(scoped_installation.bot)
        end

        test "uses parent:id for internal Apps with the per-repo rate limit capability scoped to more than one repository" do
          app = create_privileged_app_with_capabilities(capabilities: { per_repo_rate_limit: true })

          user                     = create(:user)
          repository               = create(:repository, owner: user)
          other_repository         = create(:repository, owner: user)
          integration_installation = make_integration_installation(integration: app, repositories: [repository, other_repository], permissions: { "metadata" => :read })
          scoped_installation      = make_scoped_integration_installation(parent: integration_installation, repositories: [repository, other_repository])

          assert_equal "installation-#{integration_installation.id}", RateLimitKey.for(scoped_installation.bot)
        end
      end

      context "with a SiteScopedIntegrationInstallation" do
        test "returns parent:id" do
          GitHub.flipper[:disabled_global_apps].disable

          user        = create(:user)
          repo        = create(:repository, owner: user)
          integration = create_unlimited_global_integration
          result = SiteScopedIntegrationInstallation::Creator.perform(
            integration,
            user,
            repositories: [repo],
          )
          assert_predicate result, :success?
          expected = "site-installation-#{result.installation.id}"
          assert_equal expected, RateLimitKey.for(result.installation.bot)
        end

        test "sets a repository ID in the key for internal Apps with the per-repo rate limit capability scoped to one repository" do
          GitHub.flipper[:disabled_global_apps].disable

          user = create(:user)
          repo = create(:repository, owner: user)
          integration = create_unlimited_global_integration(capabilities: { per_repo_rate_limit: true })
          result = SiteScopedIntegrationInstallation::Creator.perform(
            integration,
            user,
            repositories: [repo],
          )

          assert_predicate result, :success?
          expected = "site-installation-#{integration.id}-#{result.installation.target_id}-#{repo.id}"
          assert_equal expected, RateLimitKey.for(result.installation.bot)
        end

        test "sets a repository ID in the key for internal Apps with the per-repo rate limit capability scoped to more than one repository" do
          GitHub.flipper[:disabled_global_apps].disable

          user = create(:user)
          repo = create(:repository, owner: user)
          other_repo = create(:repository, owner: user)
          integration = create_unlimited_global_integration(capabilities: { repo_owner_rate_limit: true })
          result = SiteScopedIntegrationInstallation::Creator.perform(
            integration,
            user,
            repositories: [repo, other_repo],
          )

          assert_predicate result, :success?
          expected = "site-installation-#{integration.id}-#{result.installation.target_id}"
          assert_equal expected, RateLimitKey.for(result.installation.bot)
        end

        test "sets a repository ID in the key for internal Apps with the per-repo rate limit capability scoped to more than one repository with org" do
          GitHub.flipper[:disabled_global_apps].disable

          org = create(:organization)
          repo = create(:repository, owner: org)
          other_repo = create(:repository, owner: org)
          integration = create_unlimited_global_integration(capabilities: { repo_owner_rate_limit: true })
          result = SiteScopedIntegrationInstallation::Creator.perform(
            integration,
            org,
            repositories: [repo, other_repo],
          )

          assert_predicate result, :success?
          expected = "site-installation-#{integration.id}-#{result.installation.target_id}"
          assert_equal expected, RateLimitKey.for(result.installation.bot)
        end
      end

      context "without an installation" do
        test "returns integration:id" do
          integration = create(:integration)
          repo  = create(:repository)

          expected = "integration-#{integration.key}"
          assert_equal expected, RateLimitKey.for(integration.bot)
        end
      end
    end

    context "User" do
      test "returns user:id" do
        user = create(:user)
        assert_equal "user-#{user.id}", RateLimitKey.for(user)
      end
    end

    context "OauthApplication" do
      test "returns app:client_id" do
        app = build(:oauth_application, key: "abcdef")
        assert_equal "app-abcdef", RateLimitKey.for(app)
      end
    end

    context "Integration" do
      test "returns integration:client_id" do
        app = create(:integration)
        assert_equal "integration-#{app.key}", RateLimitKey.for(app)
      end
    end

    context "ProximaServiceIdentity" do
      test "computes correct key" do
        psi = ProximaServiceIdentity.new(service_name: "foo", tenant_shortcode: "bar")
        assert_equal "psi-foo-bar", RateLimitKey.for(psi)
      end
    end

    context "Object" do
      test "returns the stringified object" do
        assert_equal "1", RateLimitKey.for(1)
      end
    end
  end
end
