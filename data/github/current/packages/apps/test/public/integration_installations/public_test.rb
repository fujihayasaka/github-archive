# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationInstallations::PublicTest < GitHub::TestCase
  include IntegrationInstallations::Public

  fixtures do
    @integration = create(:integration)
    @owner = @integration.owner

    @repo = create(:repository, :minimal, owner: @owner)
  end

  context ".on_repository" do
    test "returns nil if a repository isn't provided" do
      assert_nil on_repository(@integration, nil)
    end

    test "returns nil if the repository isn't active" do
      make_integration_installation(integration: @integration, repository: @repo, permissions: { "metadata" => :read })
      @repo.update_column(:active, false); @repo.reload

      assert_nil on_repository(@integration, @repo)
    end

    test "returns nil if there isn't an installation on the target" do
      assert_nil on_repository(@integration, @repo)
    end

    test "returns nil when the installation doesn't have repository access" do
      make_integration_installation(integration: @integration, target: @owner)
      assert_nil on_repository(@integration, @repo)
    end

    test "returns the installation when it has been granted repository access" do
      installation = make_integration_installation(integration: @integration, repository: @repo, permissions: { "metadata" => :read })
      assert_equal installation, on_repository(@integration, @repo)
    end
  end

  context ".on_all_repositories_for_targets" do
    test "returns the installation when it has been granted repository access" do
      org = create(:organization)
      installation = make_integration_installation(target: org, permissions: { "metadata" => :read })

      assert_equal on_all_repositories_for_targets([org.id]), [installation]
    end
  end
end
