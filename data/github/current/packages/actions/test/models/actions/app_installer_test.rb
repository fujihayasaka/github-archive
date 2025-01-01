# typed: true
# frozen_string_literal: true

require "test_helper"

class ActionsAppInstallerTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)
    @trigger_id = create(:actions_automatic_installation_trigger, integration: @launch_app).id
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    GitHub.stubs(:launch_github_app).returns(@launch_app)
  end

  def installer(repo)
    Actions::AppInstaller.new(repo)
  end

  context "#enable_actions_app" do
    test "installs the Actions app" do
      repo = create(:repository)
      installer = installer(repo)

      refute repo.actions_app_installed?

      installer.enable_actions_app(entry_point: :test_case)
      assert repo.actions_app_installed?
    end

    test "installs the Actions app when the owner installation exists" do
      owner = create(:organization)
      installer(create(:repository, owner: owner)).enable_actions_app(entry_point: :test_case)

      assert_equal 1, GitHub.launch_github_app.installations_on(owner).size

      repo = create(:repository, owner: owner)
      refute repo.actions_app_installed?

      installer(repo).enable_actions_app(entry_point: :test_case)
      assert repo.actions_app_installed?
    end

    test "no op when the Actions app is already installed" do
      repo = create(:repository)
      installer(repo).enable_actions_app(entry_point: :test_case)
      assert repo.actions_app_installed?

      installer(repo).enable_actions_app(entry_point: :test_case)
      assert repo.actions_app_installed?
    end


    test "uses the input actor when the owner installation exists" do
      org = create(:organization)

      installer(create(:repository, owner: org)).enable_actions_app(entry_point: :test_case)

      second_admin = create(:user)
      org.add_admin(second_admin)
      org.reload

      refute_equal org.admins.first, second_admin

      repo = create(:repository, owner: org)

      IntegrationInstallation::Editor.expects(:append).with(
        GitHub.launch_github_app.installations_on(org).first,
        repositories: [repo],
        editor: second_admin,
        performed_automatically: false,
        entry_point: :test_case,
      )

      installer(repo).enable_actions_app(actor: second_admin, entry_point: :test_case)
    end

    test "uses the input actor when the owner installation does not exist" do
      org = create(:organization)

      second_admin = create(:user)
      org.add_admin(second_admin)
      org.reload

      refute_equal org.admins.first, second_admin

      repo = create(:repository, owner: org)

      GitHub.launch_github_app.expects(:install_on).with(
        org,
        repositories: [repo],
        installer: second_admin,
        trigger_id: nil,
        entry_point: :test_case
      )

      installer(repo).enable_actions_app(actor: second_admin, entry_point: :test_case)
    end

    test "performed automatically for installation creation when the actor does not have installation permissions" do
      org = create(:organization)

      random_user = create(:user)

      refute_equal org.admins.first, random_user

      repo = create(:repository, owner: org)

      GitHub.launch_github_app.expects(:install_on).with(
        org,
        repositories: [repo],
        installer: org.admins.first,
        trigger_id: @trigger_id,
        entry_point: :test_case
      )

      installer(repo).enable_actions_app(actor: random_user, entry_point: :test_case)
    end

    test "performed automatically for installation editing when the actor does not have installation permissions" do
      org = create(:organization)
      installer(create(:repository, owner: org)).enable_actions_app(entry_point: :test_case)

      random_user = create(:user)

      refute_equal org.admins.first, random_user

      repo = create(:repository, owner: org)

      IntegrationInstallation::Editor.expects(:append).with(
        GitHub.launch_github_app.installations_on(org).first,
        repositories: [repo],
        editor: org.admins.first,
        performed_automatically: true,
        entry_point: :test_case,
      )

      installer(repo).enable_actions_app(actor: random_user, entry_point: :test_case)
    end

    test "passes nil install trigger when the InstallTrigger does not exist" do
      org = create(:organization)

      assert IntegrationInstallTrigger.find(@trigger_id).delete
      assert_nil IntegrationInstallTrigger.latest(integration: GitHub.launch_github_app, install_type: :actions_automatic_installation)

      random_user = create(:user)

      refute_equal org.admins.first, random_user

      repo = create(:repository, owner: org)

      GitHub.launch_github_app.expects(:install_on).with(
        org,
        repositories: [repo],
        installer: org.admins.first,
        trigger_id: nil,
        entry_point: :test_case
      )

      installer(repo).enable_actions_app(actor: random_user, entry_point: :test_case)
    end
  end
end
