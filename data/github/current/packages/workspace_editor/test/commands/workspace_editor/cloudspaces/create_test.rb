# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../fake_create_result"

module WorkspaceEditor::Cloudspaces
  class CreateTest < GitHub::TestCase
    include DogstatsTestHelpers
    include CodespacesPlanFixtures
    include GitHub::LoggerHelper

    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
    fixtures do
      @owner = create(:user)
      @ce_org = create(:workspace_editor_copilot_enterprise_organization, admin: @owner)
      @repository = create(:repository, owner: @ce_org, from_example: :simple)
      @master_head = @repository.heads.find_or_build(@repository.default_branch)
      head_ref = @repository.heads.create("patch-1", @master_head.target, @owner)
      head_ref.append_commit({ message: "some changes", committer: @owner }, @owner) do |files|
        files.add("file001", "foo")
      end
      @pull_request = create(:pull_request, repository: @repository, base_repository: @repository, head_repository: @repository,  user: @owner, base_ref: @repository.default_branch, head_ref: "patch-1")
      @location = "EastUs"
      @operation = create(:codespaces_async_operation, operation: :create_codespace)
      @base_oid = Codespaces::GetTargetRef.call(repository: @repository, name_or_oid: @repository.default_branch).target_oid
    end

    setup do
      make_trusted_oauth_apps_owner
      @integration = create(:codespaces_integration)
      User.any_instance.stubs(:workspace_editor_preview_enabled?).returns(true)

      Codespaces::Secret.stubs(:assemble).returns([])
      CloudEnvironments::Public.stubs(create: FakeCreateResult.new(owner: @owner, repository_id: @repository.id, pull_request: @pull_request))
    end

    def new_pr!(repository, owner = repository.owner, branch_name = SecureRandom.hex)
      ref = repository.heads.find_or_build(repository.default_branch)
      head_ref = repository.heads.create(branch_name, ref.target, owner)
      head_ref.append_commit({ message: "some changes", committer: owner }, owner) do |files|
        files.add("file001", "foo")
      end

      create(:pull_request, repository: repository, base_repository: repository, head_repository: repository,  user: owner, base_ref: "master", head_ref: branch_name)
    end

    context "expected environment options", skip_enterprise: true do

      test "idle timeout controlled by dial" do
        FakeVSOServer.reset!
        CloudEnvironments::Public.unstub(:create)

        result = WorkspaceEditor::Cloudspaces::Create.call(
          owner: @owner,
          repository_id: @repository.id,
          pull_request_number: @pull_request.number,
          location: @location,
          operation: @operation,
        )

        environment = FakeVSOServer.environments_created.last

        assert_equal 15, environment["autoShutdownDelayMinutes"] # default value
        WorkspaceEditor::Cloudspaces::Dials::IdleTimeout.update("60")
        result = WorkspaceEditor::Cloudspaces::Create.call(
          owner: @owner,
          repository_id: @repository.id,
          pull_request_number: @pull_request.number,
          location: @location,
          operation: @operation,
        )
        environment = FakeVSOServer.environments_created.last
        assert_equal 60, environment["autoShutdownDelayMinutes"]
      end

      test "sets expected environment options for hadron when 2 way file syncing is enabled" do
        FakeVSOServer.reset!
        GitHub.flipper[:hadron_use_two_way_file_syncer].enable
        CloudEnvironments::Public.unstub(:create)

        result = WorkspaceEditor::Cloudspaces::Create.call(
          owner: @owner,
          repository_id: @repository.id,
          pull_request_number: @pull_request.number,
          location: @location,
          operation: @operation,
        )

        environment = FakeVSOServer.environments_created.last

        assert_equal result.workspace_editor_cloudspace.cloud_environment.name, environment["friendlyName"]
        assert environment["experimentalFeatures"]["fileSyncerWithBridge"]
        assert environment["features"]["fileSyncerWithBridge"]
        refute environment["experimentalFeatures"]["copilotWorkspace"]
      end

      test "sets expected environment options for hadron when 2 way file syncing is disabled" do
        FakeVSOServer.reset!
        GitHub.flipper[:hadron_use_two_way_file_syncer].disable
        CloudEnvironments::Public.unstub(:create)

        result = WorkspaceEditor::Cloudspaces::Create.call(
          owner: @owner,
          repository_id: @repository.id,
          pull_request_number: @pull_request.number,
          location: @location,
          operation: @operation,
        )

        environment = FakeVSOServer.environments_created.last

        assert_equal result.workspace_editor_cloudspace.cloud_environment.name, environment["friendlyName"]
        refute environment["experimentalFeatures"]["fileSyncerWithBridge"]
        refute environment["features"]["fileSyncerWithBridge"]
        refute environment["experimentalFeatures"]["copilotWorkspace"]
      end
    end

    context "validations", skip_enterprise: true do
      test "it prevents creation when the repository is disabled" do
        disabled_repository = create(:repository, owner: @ce_org, disabled_at: Time.now, from_example: :simple)
        pr = new_pr!(disabled_repository, @owner)

        assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Usage not allowed: repository is disabled" do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: disabled_repository.id,
            pull_request_number: pr.number,
            location: @location,
            operation: @operation,
          )
        end
      end

      test "it prevents creation when the repository has a DMCA takedown" do
        disabled_repository = create(:repository, :dmca, owner: @ce_org, from_example: :simple)
        pr = new_pr!(disabled_repository, @owner)

        assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Usage not allowed: repository is disabled" do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: disabled_repository.id,
            pull_request_number: pr.number,
            location: @location,
            operation: @operation,
          )
        end
      end

      test "it prevents creation when the owner is spammy" do
        spammy_user = create(:user)
        spammy_user.mark_as_spammy

        assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Usage not allowed" do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: spammy_user,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: @location,
            operation: @operation,
          )
        end
      end

      test "it prevents creation when the repository owner is spammy" do
        spammy_repo = create(:repository, owner: @ce_org, from_example: :simple)
        pr = new_pr!(spammy_repo, @owner)
        spammy_repo.owner.mark_as_spammy

        assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Usage not allowed" do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: spammy_repo.id,
            pull_request_number: pr.number,
            location: @location,
            operation: @operation,
          )
        end
      end

      test "it prevents creation when the billable owner is spammy" do
        spammy_user = create(:user)
        spammy_user.mark_as_spammy

        create = WorkspaceEditor::Cloudspaces::Create.new(
          owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: @location,
            operation: @operation,
        )
        create.stubs(:billable_owner).returns(spammy_user)

        assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Usage not allowed" do
          create.call
        end
      end

      test "requires a billable owner" do
        create = WorkspaceEditor::Cloudspaces::Create.new(
          owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: @location,
            operation: @operation,
        )
        create.stubs(:billable_owner).returns(nil)

        assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Billable owner could not be determined for your new workspace" do
          create.call
        end
      end

      test "prevents internal region if codespaces_developer FF is disabled" do
        GitHub.flipper[:codespaces_developer].disable
        stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: Codespaces::Vscs.default_target)
        stamp.stubs(ga?: false)

        assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Location is invalid" do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: stamp.region.id,
            operation: @operation,
          )
        end
      end

      test "allows internal region if codespaces_developer FF is enabled" do
        GitHub.flipper[:codespaces_developer].enable
        stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: Codespaces::Vscs.default_target)
        stamp.stubs(ga?: false)

        assert_nothing_raised do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: stamp.region.id,
            operation: @operation,
          )
        end
      end

      test "prevents creation on a region where creates are disabled" do
        stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: Codespaces::Vscs.default_target)
        stamp.failover(creates: true, resumes: false)

        assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Location is invalid" do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: stamp.region.id,
            operation: @operation,
          )
        end
      end

      test "allows creation on a region where resumes are disabled but creates enabled" do
        stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: Codespaces::Vscs.default_target)
        stamp.failover(creates: false, resumes: true)

        assert_nothing_raised do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: stamp.region.id,
            operation: @operation,
          )
        end
      end

      test "if there is a standard sku_name passed for that user, it is valid" do
        assert_nothing_raised  do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: @location,
            operation: @operation,
            sku_name: "standardLinux32gb",
          )
        end
      end

      test "if a feature-flagged sku_name is disabled for that user, it is invalid" do
        GitHub.flipper[:codespaces_automated_testing].disable
        GitHub.flipper[::Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG.to_sym].disable(@owner)
        assert_raises_with_message ActiveModel::ValidationError, Regexp.new("'extremeLinux' is not available") do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: @location,
            operation: @operation,
            sku_name: "extremeLinux",
          )
        end
      end

      test "if a feature-flagged sku_name is enabled for that user, it is valid" do
        GitHub.flipper[::Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG.to_sym].enable(@owner)

        assert_nothing_raised do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: @location,
            operation: @operation,
            sku_name: "extremeLinux",
          )
        end
      end

      test "if a feature-flagged sku_name is enabled for the billable org, it is valid" do
        user_org = create(:workspace_editor_copilot_enterprise_organization, admin: @owner)
        create(:billing_budget, :codespaces, owner: user_org, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)
        user_org.add_member(@owner)
        user_org_public_repo = create(:repository, owner: user_org, from_example: :simple)
        user_org_public_repo.add_member(@owner)
        Codespaces::OrgPolicy.grant_billing_permission!(@owner, user_org)
        pr = new_pr!(user_org_public_repo, @owner)

        GitHub.flipper[::Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG.to_sym].disable(@owner)
        GitHub.flipper[::Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG.to_sym].enable(user_org)
        assert_nothing_raised do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: user_org_public_repo.id,
            pull_request_number: pr.number,
            location: @location,
            operation: @operation,
            sku_name: "extremeLinux",
          )
        end
      end

      test "it disallows target specification if the user does not have the flag enabled" do
        GitHub.flipper[:codespaces_developer].disable(@owner)
        assert_raises_with_message ActiveModel::ValidationError, /Vscs target specified but owner is not authorized to use this feature/ do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: @location,
            operation: @operation,
            vscs_target: "development",
          )
        end
      end

      test "it disallows vscs_target_url if the user does not have the flag enabled" do
        GitHub.flipper[:codespaces_developer].disable(@owner)
        assert_raises_with_message ActiveModel::ValidationError, /Vscs target url specified but owner is not authorized to use this feature/ do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: @location,
            operation: @operation,
            vscs_target_url: "https://vscstest.ngrok.io",
          )
        end
      end

      test "it disallows vscs_target_url if the target is not set to 'local'" do
        GitHub.flipper[:codespaces_developer].enable(@owner)
        assert_raises_with_message ActiveModel::ValidationError, /Vscs target must be 'local' to specify a devstamp URL/ do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: @location,
            operation: @operation,
            vscs_target: "development",
            vscs_target_url: "https://vscstest.ngrok.io",
          )
        end
      end

      test "vscs_target_url must be a valid URL if set" do
        GitHub.flipper[:codespaces_developer].enable(@owner)
        assert_raises_with_message ActiveModel::ValidationError, /Vscs target url is not a valid URL/ do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: @location,
            operation: @operation,
            vscs_target: "local",
            vscs_target_url: "foobar",
          )
        end

        assert_raises_with_message ActiveModel::ValidationError, /Vscs target url is not a valid URL/ do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: @location,
            operation: @operation,
            vscs_target: "local",
            vscs_target_url: "drbunix://::1",
          )
        end
      end

      test "checks the disable_codespace_creation feature flag" do
        GitHub.flipper[:disable_codespace_creation].enable
        assert_raises_with_message ActiveModel::ValidationError, /Codespace creation is temporarily unavailable/ do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: @location,
            operation: @operation,
          )
        end
      end

      test "it fails if the user does not access to the feature" do
        @owner.stubs(:workspace_editor_preview_enabled?).returns(false)
        assert_raises do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: @location,
            operation: @operation,
          )
        end
      end

      test "only requires repository read by the codespace owner" do
        ce_org = create(:workspace_editor_copilot_enterprise_organization)
        admin = ce_org.admins.first
        ce_org.allow_private_repository_forking(actor: admin)
        private_repo = create(:private_repository, owner: ce_org, from_example: :simple)
        pr = new_pr!(private_repo, admin)

        assert_raises_with_message ActiveModel::ValidationError, /Repository does not allow you to create a codespace/ do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: private_repo.id,
            pull_request_number: pr.number,
            location: @location,
            operation: @operation,
          )
        end

        private_repo.add_member_without_validation_or_notifications(@owner, action: :read)

        assert_nothing_raised do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: private_repo.id,
            pull_request_number: pr.number,
            location: @location,
            operation: @operation,
          )
        end
      end

      test "prevents creation with a closed PR" do
        @pull_request.issue.close(@owner)
        assert_raises_with_message ActiveModel::ValidationError, /Pull request is not allowed because it is closed/ do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: @pull_request.number,
            location: @location,
            operation: @operation,
          )
        end
      end

      test "allows orgs to disable codespace creation" do
        user_org = create(:workspace_editor_copilot_enterprise_organization, plan: GitHub::Plan.business, admin: @owner)
        create(:billing_budget, :codespaces, owner: user_org, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)
        user_org.add_member(@owner)
        org_private_repo = create(:org_owned_private_repository, owner: user_org, from_example: :simple)
        org_private_repo.add_member(@owner)
        Codespaces::OrgPolicy.grant_billing_permission!(@owner, user_org)
        pr = new_pr!(org_private_repo, @owner)

        user_org.update_organization_codespaces_ownership_setting(
          Configurable::OrganizationCodespacesOwnershipSetting::USER, actor: @owner) # need this to be set or will be USERS_AND_OUTSIDE_COLLABORATORS
        user_org.update_organization_codespaces_user_limit(
            Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: @owner)
        assert_raises_with_message ActiveModel::ValidationError, /Repository does not allow you to create a codespace/ do
          WorkspaceEditor::Cloudspaces::Create.call(
            owner: @owner,
            repository_id: org_private_repo.id,
            pull_request_number: pr.number,
            location: @location,
            operation: @operation,
          )
        end
      end
    end
  end
end
