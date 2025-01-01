# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/api_programmatic_grant_helpers"

module ProgrammaticActor
  class GrantTest < GitHub::TestCase
    include ApiProgrammaticGrantHelpers
    include CopilotChatIntegrationTestHelper

    fixtures do
      @user = create(:user)
    end

    def described_class
      ::ProgrammaticActor::Grant
    end

    context ".with" do
      test "returns a new instance" do
        obj = described_class.with(@user)
        assert_kind_of described_class, obj
      end
    end

    context ".with_target" do
      test "returns a scoped installation on the target when using a scoped user-to-server token" do
        repo = create(:repository, :minimal, owner: @user)
        parent_installation = make_integration_installation(target: @user, permissions: { "metadata" => :read })
        integration = parent_installation.integration

        access = integration.grant(@user, entry_point: :test_case)
        installation = make_scoped_integration_installation(parent: parent_installation, repositories: [repo])
        access.update!(installation: installation); access.reload

        @user.oauth_access = access

        assert_equal installation, described_class.with(@user).with_target(@user)
        assert_equal ScopedIntegrationInstallation, installation.class
      end

      test "returns nothing when using a scoped user-to-server token without installations on the target" do
        org = create(:organization, admin: @user)
        repo = create(:repository, :minimal, owner: org)

        parent_installation = make_integration_installation(target: org, permissions: { "metadata" => :read })
        integration = parent_installation.integration

        access = integration.grant(@user, entry_point: :test_case)
        installation = make_scoped_integration_installation(parent: parent_installation, repositories: [repo])
        access.update!(installation: installation); access.reload

        @user.oauth_access = access

        # installations are on @org
        assert_nil described_class.with(@user).with_target(@user)
      end

      test "returns an installation on the target when using a user-to-server token" do
        installation = make_integration_installation(target: @user, permissions: { "metadata" => :read })
        integration = installation.integration

        access = integration.grant(@user, entry_point: :test_case)
        @user.oauth_access = access

        assert_equal installation, described_class.with(@user).with_target(@user)
      end

      test "returns nothing when using a user-to-server token without installations on the target" do
        access = create(:integration).grant(@user, entry_point: :test_case)
        @user.oauth_access = access

        assert_nil described_class.with(@user).with_target(@user)
      end

      test "returns the grant if it has the same target" do
        access = create(:user_programmatic_access, owner: @user)
        grant = make_programmatic_access_grant(access: access, permissions: { "metadata" => :read }, repository_selection: :all)

        @user.programmatic_access = access
        assert_equal grant, described_class.with(@user).with_target(@user)
      end

      test "returns an installation on the target when using a server-to-server token" do
        installation = make_integration_installation(target: @user, permissions: { "metadata" => :read })
        bot = installation.integration.bot
        bot.installation = installation

        assert_equal installation, described_class.with(bot).with_target(@user)
      end

      test "returns nothing when using a server-to-server token without an installation on the target" do
        org = create(:organization)
        bot = make_integration_installation(target: org).integration.bot

        assert_nil described_class.with(bot).with_target(@user)
      end
    end

    context ".with_repository" do
      test "returns a scoped installation on the target when using a scoped user-to-server token" do
        repo = create(:repository, :minimal, owner: @user)
        parent_installation = make_integration_installation(target: @user, permissions: { "metadata" => :read })
        integration = parent_installation.integration

        access = integration.grant(@user, entry_point: :test_case)
        installation = make_scoped_integration_installation(parent: parent_installation, repositories: [repo])
        access.update!(installation: installation); access.reload

        @user.oauth_access = access

        assert_equal installation, described_class.with(@user).with_repository(repo)
        assert_equal ScopedIntegrationInstallation, installation.class
      end

      test "returns nothing when using a scoped user-to-server token without installations on the target" do
        user_repo = create(:repository, :minimal, owner: @user)

        org = create(:organization, admin: @user)
        repo = create(:repository, :minimal, owner: org)

        parent_installation = make_integration_installation(target: org, permissions: { "metadata" => :read })
        integration = parent_installation.integration

        access = integration.grant(@user, entry_point: :test_case)
        installation = make_scoped_integration_installation(parent: parent_installation, repositories: [repo])
        access.update!(installation: installation); access.reload

        @user.oauth_access = access

        # installations are on @org
        assert_nil described_class.with(@user).with_repository(user_repo)
      end

      test "returns an installation on the repository when using a user-to-server token" do
        repo = create(:repository, :minimal, owner: @user)
        installation = make_integration_installation(target: @user, permissions: { "metadata" => :read })
        integration = installation.integration

        access = integration.grant(@user, entry_point: :test_case)
        @user.oauth_access = access

        assert_equal installation, described_class.with(@user).with_repository(repo)
      end

      test "returns nothing when using a user-to-server token without installations on the target" do
        repo = create(:repository, :minimal, owner: @user)
        access = create(:integration).grant(@user, entry_point: :test_case)
        @user.oauth_access = access

        assert_nil described_class.with(@user).with_repository(repo)
      end

      test "returns the grant if it has the same target" do
        repo = create(:repository, :minimal, owner: @user)

        access = create(:user_programmatic_access, owner: @user)
        grant = make_programmatic_access_grant(access: access, permissions: { "metadata" => :read }, repository_selection: :all)

        @user.programmatic_access = access
        assert_equal grant, described_class.with(@user).with_repository(repo)
      end

      test "returns an installation on the target when using a server-to-server token" do
        repo = create(:repository, :minimal, owner: @user)

        installation = make_integration_installation(target: @user, permissions: { "metadata" => :read })
        bot = installation.integration.bot
        bot.installation = installation

        assert_equal installation, described_class.with(bot).with_repository(repo)
      end

      test "returns nothing when using a server-to-server token without an installation on the target" do
        repo = create(:repository, :minimal, owner: @user)
        org = create(:organization)
        bot = make_integration_installation(target: org).integration.bot

        assert_nil described_class.with(bot).with_repository(@user)
      end

      test "returns a global integration installation on the repo owner's target using a global app without find_grantable_from_permissions" do

        GitHub.flipper[:find_grantable_from_permissions].enable
        GitHub.flipper[:copilot_knowledge_bases_fgp].enable
        GitHub.flipper[:find_grantable_from_permissions].disable

        seat = create(:copilot_feature_enabled_seat)
        copilot_user = seat.assigned_user
        repo = create(:private_repository)
        integration = create(:copilot_chat_integration)
        access = integration.grant(copilot_user, entry_point: :test_case)
        copilot_user.oauth_access = access

        expected_installation = GlobalIntegrationInstallation.new(integration, repo.owner)
        actual_installation = described_class.with(copilot_user).with_repository(repo)
        assert_equal expected_installation.class, actual_installation.class
        assert_equal expected_installation.integration_id, actual_installation.integration_id
        assert_equal expected_installation.authorization_details, actual_installation.authorization_details
      end

      test "returns a global integration installation on the repo owner's target using a global app with find_grantable_from_permissions" do
        GitHub.flipper[:find_grantable_from_permissions].enable
        GitHub.flipper[:copilot_knowledge_bases_fgp].enable
        GitHub.flipper[:find_grantable_from_permissions].enable

        seat = create(:copilot_feature_enabled_seat)
        copilot_user = seat.assigned_user
        repo = create(:private_repository)
        integration = create(:copilot_chat_integration)
        access = integration.grant(copilot_user, entry_point: :test_case)
        copilot_user.oauth_access = access

        expected_installation = GlobalIntegrationInstallation.new(integration, repo.owner)
        actual_installation = described_class.with(copilot_user).with_repository(repo)
        assert_equal expected_installation.class, actual_installation.class
        assert_equal expected_installation.integration_id, actual_installation.integration_id
        assert_equal expected_installation.authorization_details, actual_installation.authorization_details
      end
    end
  end
end
