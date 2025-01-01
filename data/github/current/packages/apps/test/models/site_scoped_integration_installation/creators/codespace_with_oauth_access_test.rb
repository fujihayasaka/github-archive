# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class SiteScopedIntegrationInstallation::Creators::CodespaceWithOauthAccessTest < GitHub::TestCase
  include PermissionsHelper

  fixtures do
    @codespaces_app = create(:codespaces_integration)

    @user = create(:user)
    @user_repository = create(:repository, owner: @user)

    @user_access = @codespaces_app.grant(@user)
    @user_codespace = create(:codespace, owner: @user, repository_id: @user_repository.id)
  end

  setup do
    GitHub.flipper[:disabled_global_apps].disable
  end

  def perform(codespace:, oauth_access:, devcontainer: nil)
    entry_point = Permissions::Service::EntryPoint.lookup(:test_case)

    SiteScopedIntegrationInstallation::Creators::CodespaceWithOauthAccess.perform(
      codespace:, oauth_access:, entry_point: entry_point, devcontainer:
    )
  end

  def details_struct(installation)
    ::ScopedInstallations::AuthorizationDetails::Builder.from_hash(installation.authorization_details)
  end

  def resource_type_for(name)
    ::ScopedInstallations::AuthorizationDetails::ResourceType.for(name)
  end

  context "pre-flight validations" do
    context "global capabilities" do
      test "app must have the :installed_globally capability" do
        integration = create(:integration)
        access = integration.grant(@user)

        result = perform(codespace: @user_codespace, oauth_access: access)

        assert_predicate result, :failed?
        assert_equal "Integration can't be globally installed", result.error
      end

      test "app must not be disabled via feature flag" do
        @codespaces_app.enable_feature(:disabled_global_apps)

        result = perform(codespace: @user_codespace, oauth_access: @user_access)

        assert_predicate result, :failed?
        assert_equal "Global-Apps is disabled for this integration", result.error
      end
    end
  end

  context "with a failed result" do
    test "returns a human friendly error on ActiveRecord related failures" do
      ::Permissions::Service.expects(:grant_permissions!).raises(ActiveRecord::ConnectionTimeoutError.new("Boom"))

      GitHub.logger.expects(:warn).with(
        "gh.codespace_ssii_creator_error" => "ActiveRecord::ConnectionTimeoutError",
        "gh.codespace_ssii_creator_error_origin" => "SiteScopedIntegrationInstallation::Creators::CodespaceWithOauthAccess",
        "gh.codespace_ssii_creator_error_details" => "Boom"
      )

      assert_no_changes IntegrationInstallation.count do
        result = perform(codespace: @user_codespace, oauth_access: @user_access)

        assert_predicate result, :failed?
        assert_predicate @user_access, :destroyed?

        assert_equal "There was a problem while granting permissions", result.error
      end
    end

    test "requires the oauth access to be granted by a global app" do
      non_global_app = create(:integration)
      user_access = non_global_app.grant(@user)

      result = perform(codespace: @user_codespace, oauth_access: user_access)

      assert_predicate result, :failed?
      assert_equal "Integration can't be globally installed", result.error
    end

    test "requires :disabled_global_apps disabled" do
      GitHub.flipper[:disabled_global_apps].enable(@codespaces_app)
      result = perform(codespace: @user_codespace, oauth_access: @user_access)

      assert_predicate result, :failed?
      assert_equal "Global-Apps is disabled for this integration", result.error
    end

    test "requires the target to be accessible to the limited internal app" do
      Apps::Internal
        .stubs(:target_accessible_to_limited_app?)
        .with(@user, app: @codespaces_app)
        .returns(false)

      result = perform(codespace: @user_codespace, oauth_access: @user_access)

      assert_predicate result, :failed?
      assert_equal "This integration doesn't have access to the given target", result.error
    end
  end

  context "with a successful result" do
    test "creates a site scoped installation with access to the codespace's repository" do
      result = perform(codespace: @user_codespace, oauth_access: @user_access)
      assert_predicate result, :success?

      assert_predicate result.installation, :persisted?
      assert_equal OauthAccess.with_active_token(result.credential), @user_access

      # Repository/metadata
      assert_actor_and_subject_granted_in_permissions_table(
        actor: result.installation,
        subject: @user_repository.resources.metadata,
        action: :read
      )

      # Codespace/codespace_metadata
      assert_actor_and_subject_granted_in_permissions_table(
        actor: result.installation,
        subject: @user_codespace.resources.codespace_metadata,
        action: :read
      )
    end

    test "grants limited set of permissions to the parent repository if repo is a fork and public" do
      parent_repo = create(:repository)
      forker = create(:user)
      forked_repo = create(:fork_repository, forker: forker, fork_repo: parent_repo)
      codespace = create(:codespace, owner: forker, repository: forked_repo)

      result = perform(codespace: codespace, oauth_access: @user_access)
      assert_predicate result, :success?

      assert_actor_and_subject_granted_in_permissions_table(
        actor: result.installation,
        subject: parent_repo.resources.pull_requests_from_forks,
        action: :write
      )

      assert_actor_and_subject_granted_in_permissions_table(
        actor: result.installation,
        subject: parent_repo.resources.pull_requests_comment_only_reviews,
        action: :write
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor: result.installation,
        subject: parent_repo.resources.contents,
        action: :read
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor: result.installation,
        subject: parent_repo.resources.pull_requests,
        action: :read
      )
    end

    test "grants full set of permissions to the parent repository if repo is a fork and private" do
      org = create(:organization)
      org.allow_private_repository_forking(actor: org.admins.first)
      parent_repo = create(:private_repository, owner: org)
      forker = create(:user)
      parent_repo.add_member_without_validation_or_notifications(forker)
      forked_repo = create(:fork_repository, forker: forker, fork_repo: parent_repo)
      codespace = create(:codespace, owner: forker, repository: forked_repo)

      result = perform(codespace: codespace, oauth_access: @user_access)
      assert_predicate result, :success?

      assert_actor_and_subject_granted_in_permissions_table(
        actor: result.installation,
        subject: parent_repo.resources.pull_requests,
        action: :write
      )

      assert_actor_and_subject_granted_in_permissions_table(
        actor: result.installation,
        subject: parent_repo.resources.contents,
        action: :write
      )
    end

    test "grants access to dotfiles repository" do
      dotfiles_repo = create(:private_repository, name: "dotfiles", owner: @user)

      # No access by default
      result = perform(codespace: @user_codespace, oauth_access: @codespaces_app.grant(@user))
      refute_actor_and_subject_granted_in_permissions_table(
        actor: result.installation,
        subject: dotfiles_repo.resources.contents,
        action: :read
      )

      # Still no access after updating the codespace dotfiles repository
      @user.update_codespace_dotfiles_repository(dotfiles_repo.id, actor: @user)
      result2 = perform(codespace: @user_codespace, oauth_access: @codespaces_app.grant(@user))
      refute_actor_and_subject_granted_in_permissions_table(
        actor: result2.installation,
        subject: dotfiles_repo.resources.contents,
        action: :read
      )

      # Gets read-only access after enabling codespace dotfiles
      @user.enable_codespace_dotfiles(actor: @user)
      result3 = perform(codespace: @user_codespace, oauth_access: @codespaces_app.grant(@user))
      assert_actor_and_subject_granted_in_permissions_table(
        actor: result3.installation,
        subject: dotfiles_repo.resources.contents,
        action: :read
      )
    end

    test "does not create duplicate permissions when codespace is opened in the dotfiles_repo" do
      dotfiles_repo = create(:private_repository, name: "dotfiles", owner: @user)
      codespace_on_dotfiles_repo = create(:codespace, owner: @user, repository: dotfiles_repo)

      @user.update_codespace_dotfiles_repository(dotfiles_repo.id, actor: @user)
      @user.enable_codespace_dotfiles(actor: @user)

      # No access by default
      result = perform(codespace: codespace_on_dotfiles_repo, oauth_access: @codespaces_app.grant(@user))
      assert_predicate result, :success?

      assert_actor_and_subject_granted_in_permissions_table(
        actor: result.installation,
        subject: dotfiles_repo.resources.metadata,
        action: :read
      )

      assert_actor_and_subject_granted_in_permissions_table(
        actor: result.installation,
        subject: dotfiles_repo.resources.contents,
        action: :write
      )
    end

    test "overwrites elevated access when user has devcontainer permissions" do
      example_repo :simple, @user_codespace.repository

      Codespaces::UpdateTrustedRepositoryAccess.call(
        actor: @user,
        target: @user,
        trusted_repo_setting: Configurable::CodespaceTrustedRepositories::ALL_REPOS,
        entry_point: :test_case
      )

      another_repo = create(:private_repository, name: "another_repo", owner: @user)

      result = perform(codespace: @user_codespace, oauth_access: @user_access)
      assert_actor_and_subject_granted_in_permissions_table(
        actor: result.installation,
        subject: @user.repository_resources.contents,
        action: :read
      )

      dc_contents = %{
        {
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{@user}/*": {
                  "permissions": {
                    "contents": "write"
                  }
                },
                "#{@user_repository.nwo}": {
                  "permissions": {
                    "metadata": "read"
                  }
                }
              }
            }
          }
        }
      }

      @user_repository.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @user }, @user) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      dc = Codespaces::DevContainer.new(
        repository: @user_repository,
        oid: @user_repository.refs.find("master").target_oid,
        filepath: ".devcontainer/devcontainer.json",
        user: @user
      )

      new_codespace = create(
        :codespace,
        repository: @user_repository,
        owner: @user,
        oid: @user_repository.refs.find("master").target_oid,
        devcontainer_path: dc.filepath
      )

      # mimic user accepting org/* contents:write permissions
      perms = Codespaces::AllowedPermission.new(
        user: @user,
        repository: @user_repository,
        target_id: @user.id,
        target_type: "User",
        resource: "contents",
        action: "write"
      )

      perms.save!

      result2 = perform(
        codespace: new_codespace,
        oauth_access: @codespaces_app.grant(@user),
        devcontainer: dc
      )

      assert_actor_and_subject_granted_in_permissions_table(
        actor: result2.installation,
        subject: @user.repository_resources.contents,
        action: :write
      )
    end

    test "skips writing authorization details", feature_disabled: :mint_codespaces_token_with_authorization_details do
      result = perform(codespace: @user_codespace, oauth_access: @user_access)

      assert_predicate result, :success?
      assert_nil result.installation.authorization_details
    end

    test "uses the expected version when writing authorization details", feature_enabled: :mint_codespaces_token_with_authorization_details do
      GitHub.flipper[:use_authorization_details_v2_on_codespaces].enable
      result = perform(codespace: @user_codespace, oauth_access: @codespaces_app.grant(@user))

      assert_equal 2, result.installation.authorization_details["version"]

      GitHub.flipper[:use_authorization_details_v2_on_codespaces].disable
      result = perform(codespace: @user_codespace, oauth_access: @codespaces_app.grant(@user))

      assert_equal 1, result.installation.authorization_details["version"]
    end

    test "handles validation failures on authorization details", feature_enabled: :mint_codespaces_token_with_authorization_details do
      # Dummy data for the error
      schema = stub(uri: "dummy/schema")
      validation_error = JSON::Schema::ValidationError.new("Boom", [], "DummyAttribute", schema)
      JSON::Validator.stubs(:validate!).raises(validation_error)

      GitHub.logger.expects(:warn).with(
        "gh.codespace_ssii_creator_error" => "JSON::Schema::ValidationError",
        "gh.codespace_ssii_creator_error_origin" => "SiteScopedIntegrationInstallation::Creators::CodespaceWithOauthAccess",
        "gh.codespace_ssii_creator_error_details" => "Boom"
      )

      result = perform(codespace: @user_codespace, oauth_access: @user_access)

      assert_predicate result, :failed?
      assert_equal "There was a problem while granting permissions", result.error
    end

    test "sets authorization details in the installation", feature_enabled: :mint_codespaces_token_with_authorization_details do
      result = perform(codespace: @user_codespace, oauth_access: @user_access)
      assert_predicate result, :success?

      authorization_details = details_struct(result.installation)

      assert authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Codespace"),
        selection: [@user_codespace.id],
        resource: "codespace_metadata",
        action: :read
      )

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

    test "includes dotfiles permissions in authorization details in the installation", feature_enabled: :mint_codespaces_token_with_authorization_details do
      dotfiles_repo = create(:private_repository, name: "dotfiles", owner: @user)

      @user.update_codespace_dotfiles_repository(dotfiles_repo.id, actor: @user)
      @user.enable_codespace_dotfiles(actor: @user)

      result = perform(codespace: @user_codespace, oauth_access: @user_access)
      assert_predicate result, :success?

      authorization_details = details_struct(result.installation)

      assert authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Codespace"),
        selection: [@user_codespace.id],
        resource: "codespace_metadata",
        action: :read
      )

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

      assert authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [dotfiles_repo.id],
        resource: "metadata",
      )

      assert authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [dotfiles_repo.id],
        resource: "contents",
      )
    end

    test "sets elevated permissions in authorization details", feature_enabled: :mint_codespaces_token_with_authorization_details do
      example_repo :simple, @user_codespace.repository

      Codespaces::UpdateTrustedRepositoryAccess.call(
        actor: @user,
        target: @user,
        trusted_repo_setting: Configurable::CodespaceTrustedRepositories::ALL_REPOS,
        entry_point: :test_case
      )

      another_repo = create(:private_repository, name: "another_repo", owner: @user)
      dc_contents = %{
        {
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{@user}/*": {
                  "permissions": {
                    "contents": "write"
                  }
                },
                "#{@user_repository.nwo}": {
                  "permissions": {
                    "metadata": "read"
                  }
                }
              }
            }
          }
        }
      }

      @user_repository.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @user }, @user) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      dc = Codespaces::DevContainer.new(
        repository: @user_repository,
        oid: @user_repository.refs.find("master").target_oid,
        filepath: ".devcontainer/devcontainer.json",
        user: @user
      )

      new_codespace = create(
        :codespace,
        repository: @user_repository,
        owner: @user,
        oid: @user_repository.refs.find("master").target_oid,
        devcontainer_path: dc.filepath
      )

      # mimic user accepting org/* contents:write permissions
      perms = Codespaces::AllowedPermission.new(
        user: @user,
        repository: @user_repository,
        target_id: @user.id,
        target_type: "User",
        resource: "contents",
        action: "write"
      )

      perms.save!

      result = perform(
        codespace: new_codespace,
        oauth_access: @codespaces_app.grant(@user),
        devcontainer: dc
      )

      assert_predicate result, :success?

      authorization_details = details_struct(result.installation)

      assert authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All,
        resource: "contents",
        action: :write
      )
    end
  end
end unless GitHub.enterprise?
