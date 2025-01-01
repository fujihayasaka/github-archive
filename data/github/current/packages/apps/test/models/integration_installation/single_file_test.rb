# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationInstallationSingleFileTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @org = create(:organization, plan: "bronze")
    @repo = create(:private_repository, :minimal, owner: @org)
    @integration = create(:integration, default_permissions: { "single_file" => :read }, single_file_name: "config.yml")
    @single_file_resource = IntegrationInstallation::SingleFile.new(repository: @repo, path: "config.yml")
  end

  context "readable_by?" do
    test "returns true for an installation with single_file access whose Integration has requested the given path" do
      installation = make_integration_installation(repository: @repo, integration: @integration)
      assert @single_file_resource.readable_by?(installation)
    end

    test "returns true for an installation with contents access" do
      @integration.versions.create(default_permissions: { "contents" => :read })
      installation = make_integration_installation(repository: @repo, integration: @integration)

      assert @single_file_resource.readable_by?(installation)
    end

    test "returns true for an installation with single_file access on the entire account for the given path" do
      installation = make_integration_installation(target: @org, integration: @integration)
      assert @single_file_resource.readable_by?(installation)
    end

    test "returns true for a user who can read the repo" do
      assert @single_file_resource.readable_by?(@org.admins.first)
    end

    test "returns true for an installation with multi single_file accesses" do
      integration_multi = create(:integration, default_permissions: { "single_file" => :read }, single_file_paths: ["test.txt", "config.yml"])
      second_single_file_resource = IntegrationInstallation::SingleFile.new(repository: @repo, path: "test.txt")

      installation = make_integration_installation(repository: @repo, integration: integration_multi)
      assert @single_file_resource.readable_by?(installation)
      assert second_single_file_resource.readable_by?(installation)
    end

    test "returns false for an installation without single_file access" do
      @integration.versions.create(default_permissions: { "issues" => :read })
      installation = make_integration_installation(repository: @repo, integration: @integration)

      refute @single_file_resource.readable_by?(installation)
    end

    test "returns false for an installation with single_file access whose Integration has not requested the given path" do
      integration = create(:integration, default_permissions: { "single_file" => :read }, single_file_name: "database.yml")

      installation = make_integration_installation(repository: @repo, integration: integration)
      refute @single_file_resource.readable_by?(installation)
    end

    test "returns false for an installation with single_file access whose Integration has requested this filename, but a different path" do
      integration = create(:integration, default_permissions: { "single_file" => :read }, single_file_name: "other_dir/config.yml")

      installation = make_integration_installation(repository: @repo, integration: integration)
      refute @single_file_resource.readable_by?(installation)
    end

    test "returns false for an installation with single_file access on the entire account, whose Integration has not requested the given path" do
      integration = create(:integration, default_permissions: { "single_file" => :read }, single_file_name: "database.yml")

      installation = make_integration_installation(target: @org, integration: integration)
      refute @single_file_resource.readable_by?(installation)
    end

    test "returns false for an installation with multi single_file accesses but not the requested file" do
      integration_multi = create(:integration, default_permissions: { "single_file" => :read }, single_file_paths: ["test.txt", "another_example.md"])

      installation = make_integration_installation(repository: @repo, integration: integration_multi)
      refute @single_file_resource.readable_by?(installation)
    end

    test "returns false for a Bot without an installation" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      bot = @integration.bot
      assert_nil bot.installation

      refute @single_file_resource.readable_by?(bot)
      assert_includes GitHub.dogstats.increments("integration.single_file_name").first.tags, "missing:installation"
    end

    test "returns false when the path is nil" do
      single_file_resource = IntegrationInstallation::SingleFile.new(repository: @repo, path: nil)
      refute single_file_resource.readable_by?(@integration.bot)
    end

    context "ScopedIntegrationInstallation" do
      test "returns true for an installation with single_file access whose Integration has requested the given path" do
        parent       = make_integration_installation(repository: @repo, integration: @integration)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])

        assert @single_file_resource.readable_by?(installation)
      end

      test "returns true for an installation with contents access" do
        @integration.versions.create(default_permissions: { "contents" => :read })

        parent       = make_integration_installation(repository: @repo, integration: @integration)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])

        assert @single_file_resource.readable_by?(installation)
      end

      test "returns false for an installation without single_file access" do
        @integration.versions.create(default_permissions: { "issues" => :read })

        parent       = make_integration_installation(repository: @repo, integration: @integration)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])

        refute @single_file_resource.readable_by?(installation)
      end

      test "returns false for an installation with single_file access whose Integration has not requested the given path" do
        integration = create(:integration, default_permissions: { "single_file" => :read }, single_file_name: "database.yml")

        parent       = make_integration_installation(repository: @repo, integration: integration)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])

        refute @single_file_resource.readable_by?(installation)
      end

      test "returns false for an installation with single_file access whose Integration has requested this filename, but a different path" do
        integration = create(:integration, default_permissions: { "single_file" => :read }, single_file_name: "other_dir/config.yml")

        parent       = make_integration_installation(repository: @repo, integration: integration)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])

        refute @single_file_resource.readable_by?(installation)
      end
    end
  end

  context "writable_by?" do
    test "returns true for an installation with :write single_file access whose Integration has requested the given path" do
      @integration.versions.create(default_permissions: { "single_file" => :write }, single_file_name: "config.yml")
      installation = make_integration_installation(repository: @repo, integration: @integration)

      assert @single_file_resource.writable_by?(installation)
    end

    test "returns true for an installation with :write contents access" do
      installation = make_integration_installation(repository: @repo,
        integration: @integration, permissions: { "contents" => :write })

      assert @single_file_resource.writable_by?(installation)
    end

    test "returns true for a user who can write to the repo" do
      assert @single_file_resource.writable_by?(@org.admins.first)
    end

    test "returns true for an installation with multi single_file accesses" do
      integration_multi = create(:integration, default_permissions: { "single_file" => :write }, single_file_paths: ["test.txt", "config.yml"])
      second_single_file_resource = IntegrationInstallation::SingleFile.new(repository: @repo, path: "test.txt")

      installation = make_integration_installation(repository: @repo, integration: integration_multi)
      assert @single_file_resource.writable_by?(installation)
      assert second_single_file_resource.writable_by?(installation)
    end

    test "returns false for an installation without single_file access" do
      installation = make_integration_installation(repository: @repo,
        integration: @integration, permissions: { "issues" => :write })

      refute @single_file_resource.writable_by?(installation)
    end

    test "returns false for an installation with :read single_file access" do
      installation = make_integration_installation(repository: @repo,
        integration: @integration, permissions: { "issues" => :read })

      refute @single_file_resource.writable_by?(installation)
    end

    test "returns false for an installation with :write single_file access whose Integration has not requested the given path" do
      integration = create(:integration, default_permissions: { "single_file" => :write }, single_file_name: "database.yml")
      installation = make_integration_installation(repository: @repo, integration: integration)

      refute @single_file_resource.writable_by?(installation)
    end

    test "returns false for an installation with multi single_file accesses but not the requested file" do
      integration_multi = create(:integration, default_permissions: { "single_file" => :write }, single_file_paths: ["test.txt", "another_example.md"])

      installation = make_integration_installation(repository: @repo, integration: integration_multi)
      refute @single_file_resource.writable_by?(installation)
    end

    test "returns false for an installation with multi single_file accesses with :read single_file access" do
      integration_multi = create(:integration, default_permissions: { "single_file" => :read }, single_file_paths: ["test.txt", "another_example.md"])

      installation = make_integration_installation(repository: @repo, integration: integration_multi)
      refute @single_file_resource.writable_by?(installation)
    end

    context "ScopedIntegrationInstallation" do
      test "returns true for an installation with :write single_file access whose Integration has requested the given path" do
        @integration.versions.create(default_permissions: { "single_file" => :write }, single_file_name: "config.yml")

        parent       = make_integration_installation(repository: @repo, integration: @integration)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])

        assert @single_file_resource.writable_by?(installation)
      end

      test "returns true for an installation with :write contents access" do
        parent = make_integration_installation(repository: @repo,
          integration: @integration, permissions: { "contents" => :write })

        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])

        assert @single_file_resource.writable_by?(installation)
      end

      test "returns false for an installation without single_file access" do
        parent = make_integration_installation(repository: @repo,
          integration: @integration, permissions: { "issues" => :write })

        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])

        refute @single_file_resource.writable_by?(installation)
      end

      test "returns false for an installation with :read single_file access" do
        parent = make_integration_installation(repository: @repo,
          integration: @integration, permissions: { "issues" => :read })

        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])

        refute @single_file_resource.writable_by?(installation)
      end

      test "returns false for an installation with :write single_file access whose Integration has not requested the given path" do
        integration  = create(:integration, default_permissions: { "single_file" => :write }, single_file_name: "database.yml")
        parent       = make_integration_installation(repository: @repo, integration: integration)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])

        refute @single_file_resource.writable_by?(installation)
      end
    end
  end
end
