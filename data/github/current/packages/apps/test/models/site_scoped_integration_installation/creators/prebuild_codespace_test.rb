# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class SiteScopedIntegrationInstallation::Creators::PrebuildCodespaceTest < GitHub::TestCase
  include PermissionsHelper

  fixtures do
    @codespaces_app = create(:codespaces_integration)

    @user = create(:user)
    @user_repository = create(:repository, owner: @user)
  end

  setup do
    disable_feature_flag(:disabled_global_apps)
  end

  def perform(integration: @codespaces_app, repository:, branch: "master")
    entry_point = Permissions::Service::EntryPoint.lookup(:test_case)

    SiteScopedIntegrationInstallation::Creators::PrebuildCodespace.perform(
      integration:, repository:, code_path: "test", branch:, entry_point:
    )
  end

  context "with a failed result" do
    test "returns a human friendly error on ActiveRecord related failures" do
      SiteScopedIntegrationInstallation.any_instance.expects(:save!).raises(ActiveRecord::ConnectionTimeoutError.new("Boom"))

      GitHub.logger.expects(:warn).with(
        "gh.codespace_ssii_creator_error" => "ActiveRecord::ConnectionTimeoutError",
        "gh.codespace_ssii_creator_error_origin" => "SiteScopedIntegrationInstallation::Creators::PrebuildCodespace",
        "gh.codespace_ssii_creator_error_details" => "Boom"
      )

      assert_no_changes IntegrationInstallation.count do
        result = perform(repository: @user_repository)
        assert_predicate result, :failed?

        assert_equal "There was a problem while granting permissions", result.error
      end
    end

    test "does not raise on a read connection while reporting the error" do
      SiteScopedIntegrationInstallation.any_instance.expects(:save!).raises(ActiveRecord::ConnectionTimeoutError.new("Boom"))

      ActiveRecord::Base.connected_to(role: :reading) do
        result = perform(repository: @user_repository)
        assert_predicate result, :failed?

        assert_equal "There was a problem while granting permissions", result.error
      end
    end

    test "requires :disabled_global_apps disabled" do
      enable_feature_flag(:disabled_global_apps, @codespaces_app)
      result = perform(repository: @user_repository)

      assert_predicate result, :failed?
      assert_equal "Global-Apps is disabled for this integration", result.error
    end

    test "requires the target to be accessible to the limited internal app" do
      Apps::Privileged
        .stubs(:target_accessible_to_limited_app?)
        .with(@user, app: @codespaces_app)
        .returns(false)

      result = perform(repository: @user_repository)

      assert_predicate result, :failed?
      assert_equal "This integration doesn't have access to the given target", result.error
    end
  end

  context "with a successful result" do
    test "creates an installation and read permissions" do
      branch = "master"
      org = create(:team_org)
      org.add_member(@user)
      repo = create(:repository, owner: org, from_example: :simple)
      repo.add_member(@user)

      another_repo = create(:repository, owner: org, from_example: :simple)
      another_repo.add_member(@user)

      result = perform(repository: repo, branch: branch)
      assert_predicate result, :success?

      installation = result.installation

      permissions = Permission.where(actor: installation)
      assert permissions.all? { |p| p.action == "read" }

      refute another_repo.resources.contents.writable_by?(installation)
    end

    test "sets expiration on the token and on the permissions" do
      result = perform(repository: @user_repository)
      assert_predicate result, :success?

      installation = result.installation
      assert installation.expires_at > 24.hours.from_now
    end

    test "traces the synthesis of authorization details" do
      perform(repository: @user_repository)
      span = find_span_by(name: "CodespaceAuthorizationDetailsWriter.synthesize_authorization_details")

      assert_equal 2, span.attributes["gh.authorization_details_version"]
    end

    test "handles validation failures on authorization details" do
      # Dummy data for the error
      schema = stub(uri: "dummy/schema")
      validation_error = JSON::Schema::ValidationError.new("Boom", [], "DummyAttribute", schema)
      JSON::Validator.stubs(:validate!).raises(validation_error)

      GitHub.logger.expects(:warn).with(
        "gh.codespace_ssii_creator_error" => "JSON::Schema::ValidationError",
        "gh.codespace_ssii_creator_error_origin" => "SiteScopedIntegrationInstallation::Creators::PrebuildCodespace",
        "gh.codespace_ssii_creator_error_details" => "Boom"
      )

      result = perform(repository: @user_repository)

      assert_predicate result, :failed?
      assert_equal "There was a problem while granting permissions", result.error
    end

    test "sets authorization details on the installation" do
      result = perform(repository: @user_repository)
      assert_predicate result, :success?

      authorization_details = details_struct(result.installation)

      assert authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Organization"),
        selection: [@user.id],
        resource: "organization_packages",
        action: :read
      )

      assert authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [@user_repository.id],
        resource: "metadata",
        action: :read
      )
    end

    test "sets authorization details with multiple repository specific permissions" do
      branch = "master"
      org = create(:team_org)
      org.add_member(@user)

      repo = create(:repository, owner: org, from_example: :simple)
      repo.add_member(@user)

      another_repo = create(:private_repository, owner: org, from_example: :simple)
      another_repo.add_member(@user)

      another_other_repo = create(:private_repository, owner: org, from_example: :simple)
      another_other_repo.add_member(@user)

      # want to test the combination of multiple devcontainer configurations
      dc_contents = %{
        {
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{repo.nwo}": {
                  "permissions": {
                    "packages": "read",
                    "contents": "read"
                  }
                },
                "#{another_repo.nwo}": {
                  "permissions": {
                    "packages": "read",
                    "contents": "read"
                  }
                }
              }
            }
          }
        }
      }

      another_dc_contents = %{
        {
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{another_other_repo.nwo}": {
                  "permissions": {
                    "packages": "read",
                    "contents": "read"
                  }
                },
                "#{another_repo.nwo}": {
                  "permissions": {
                    "packages": "read",
                    "pull_requests": "read"
                  }
                }
              }
            }
          }
        }
      }

      dev_container_path = ".devcontainer/devcontainer.json"
      another_dev_container_path = ".devcontainer/one/devcontainer.json"

      repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
        files.add(dev_container_path, dc_contents)
      end

      repo.refs.find("master").append_commit({ message: "add devcontainer2 json file", committer: repo.owner }, repo.owner) do |files|
        files.add(another_dev_container_path, another_dc_contents)
      end

      configuration = create(:codespace_prebuild_configuration, repository: repo, branch: branch, devcontainer_path: dev_container_path)

      another_configuration = create(:codespace_prebuild_configuration, repository: repo, branch: branch, devcontainer_path: another_dev_container_path)

      # mimic user accepting org/another_repo in the first devcontainer configuration
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "metadata", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_other_repo.id, target_type: "Repository", resource: "metadata", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: another_configuration.id)

      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "packages", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "contents", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "pull_requests", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: another_configuration.id)

      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_other_repo.id, target_type: "Repository", resource: "packages", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: another_configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_other_repo.id, target_type: "Repository", resource: "contents", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: another_configuration.id)

      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: repo.id, target_type: "Repository", resource: "contents", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)

      result = perform(repository: repo, branch: branch)
      assert_predicate result, :success?

      authorization_details = details_struct(result.installation)

      assert authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Organization"),
        selection: [org.id],
        resource: "organization_packages"
      )

      assert authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [repo.id],
        resource: "metadata"
      )

      assert authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [another_repo.id, another_other_repo.id],
        resource: "contents"
      )

      assert authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [another_repo.id, another_other_repo.id],
        resource: "metadata"
      )

      assert authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [another_repo.id],
        resource: "pull_requests"
      )
    end

    test "avoids duplicates coming from DC configs" do
      branch = "master"
      org = create(:team_org)
      org.add_member(@user)

      repo = create(:repository, owner: org, from_example: :simple)
      repo.add_member(@user)

      another_repo = create(:private_repository, owner: org, from_example: :simple)
      another_repo.add_member(@user)

      another_other_repo = create(:private_repository, owner: org, from_example: :simple)
      another_other_repo.add_member(@user)

      # want to test the combination of multiple devcontainer configurations
      dc_contents = %{
        {
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{repo.nwo}": {
                  "permissions": {
                    "contents": "read"
                  }
                },
                "#{another_repo.nwo}": {
                  "permissions": {
                    "packages": "read",
                    "contents": "read"
                  }
                }
              }
            }
          }
        }
      }

      another_dc_contents = %{
        {
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{another_other_repo.nwo}": {
                  "permissions": {
                    "packages": "read",
                    "contents": "read"
                  }
                },
                "#{another_repo.nwo}": {
                  "permissions": {
                    "packages": "read",
                    "pull_requests": "read"
                  }
                }
              }
            }
          }
        }
      }

      dev_container_path = ".devcontainer/devcontainer.json"
      another_dev_container_path = ".devcontainer/one/devcontainer.json"

      repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
        files.add(dev_container_path, dc_contents)
      end

      repo.refs.find("master").append_commit({ message: "add devcontainer2 json file", committer: repo.owner }, repo.owner) do |files|
        files.add(another_dev_container_path, another_dc_contents)
      end

      configuration = create(:codespace_prebuild_configuration, repository: repo, branch: branch, devcontainer_path: dev_container_path)

      another_configuration = create(:codespace_prebuild_configuration, repository: repo, branch: branch, devcontainer_path: another_dev_container_path)

      # mimic user accepting org/another_repo in the first devcontainer configuration
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "metadata", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_other_repo.id, target_type: "Repository", resource: "metadata", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: another_configuration.id)

      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "packages", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "contents", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "pull_requests", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: another_configuration.id)

      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_other_repo.id, target_type: "Repository", resource: "packages", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: another_configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_other_repo.id, target_type: "Repository", resource: "contents", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: another_configuration.id)

      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: repo.id, target_type: "Repository", resource: "contents", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)

      result = perform(repository: repo, branch: branch)
      assert_predicate result, :success?

      authorization_details = details_struct(result.installation)

      assert authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [repo.id],
        resource: "metadata"
      )
    end
    # For more tests, see /packages/codespaces/test/models/codespaces/tokens_test.rb#L969
  end
end unless GitHub.enterprise?
