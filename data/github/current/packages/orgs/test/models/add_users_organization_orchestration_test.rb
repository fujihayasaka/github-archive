# typed: true
# frozen_string_literal: true

require "test_helper"

class AddUsersOrganizationOrchestrationTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @org = create(:organization, admin: @owner)

    @user = create(:user)

    @business_owner = create(:user)
    @business_org = create(:organization, admin: @business_owner)
    @business = create(:business, organizations: [@business_org], owners: [@business_owner])

    @repo = create(:private_repository, owner: @org)
    @collab = create(:user)
    @repo.add_member(@collab)

    @unaffiliated_user = create(:user)
    @business.add_user_accounts([@unaffiliated_user.id], business_roles_bitfield: 0)

    unless GitHub.single_business_environment?
      @emu = create(:emu)
      @emu_business = @emu.enterprise_managed_business
      @emu_owner = @emu_business.owners.first
      @emu_org = create(:organization, admin: @emu_owner, business: @emu_business)
    end
  end

  context "step create_abilities" do
    test "adds abilities for user to be a member of the organization" do
      refute @org.member?(@user)
      OrganizationOrchestration.add_users(actor: @owner, organizations: [@org], teams: [], users: [@user]).execute(synchronous: true)
      assert @org.member?(@user)
    end

    test "skips further steps if no new members are added" do
      OrganizationOrchestration.add_users(actor: @owner, organizations: [@org], teams: [], users: [@owner]).execute(synchronous: true)
      assert_equal "skipped", OrganizationOrchestration.last&.state
    end

    unless GitHub.single_business_environment?
      test "creates business user account for user" do
        assert_nil @business.business_user_account_for(@user)
        OrganizationOrchestration.add_users(actor: @owner, business_id: @business.id, organizations: [@business_org], teams: [], users: [@user]).execute(synchronous: true)
        refute_nil @business.business_user_account_for(@user)
      end
    end
  end

  context "step update_license_usage" do
    unless GitHub.single_business_environment?
      test "updates licenses consumed" do
        assert_difference "@business.reload.total_consumed_licenses", +1 do
          perform_enqueued_jobs only: [OrganizationOrchestrationJob, BusinessUpdateLicenseUsageJob] do
            OrganizationOrchestration.add_users(actor: @owner, business_id: @business.id, organizations: [@business_org], teams: [], users: [@user]).execute(synchronous: false)
          end
        end
      end
    end
  end

  context "step update_business_user_account_attributes" do
    unless GitHub.single_business_environment?
      test "updates attributes for all users" do
        refute @business.member?(@unaffiliated_user)
        refute @business.business_user_account_for(@unaffiliated_user).has_business_role?(:member)
        perform_enqueued_jobs only: [OrganizationOrchestrationJob, BusinessUserAccountUpdateAttributesJob] do
          OrganizationOrchestration.add_users(actor: @business_owner, business_id: @business.id, organizations: [@business_org], teams: [], users: [@unaffiliated_user]).execute(synchronous: false)
        end
        assert @business.member?(@unaffiliated_user)
        assert @business.business_user_account_for(@unaffiliated_user).has_business_role?(:member)
      end
    end
  end

  context "step update_organization_collaborators" do
    unless GitHub.single_business_environment?
      test "deletes organization collaborator records for users that are added" do
        OrganizationCollaborator.backfill_for_org(@org)
        assert_nil @business.business_user_account_for(@collab)
        refute_nil OrganizationCollaborator.with_org_and_user(@org, @collab).first
        OrganizationOrchestration.add_users(actor: @owner, organizations: [@org], teams: [], users: [@collab], business_id: @business.id).execute(synchronous: true)
        assert_nil OrganizationCollaborator.with_org_and_user(@org, @collab).first
        refute_nil @business.business_user_account_for(@collab)
      end
    end
  end

  context "step publicize_org_memberships" do
    if GitHub.default_org_membership_visibility_public?
      test "publicizes org memberships" do
        OrganizationOrchestration.add_users(actor: @owner, organizations: [@business_org], teams: [], users: [@user], business_id: @business.id).execute(synchronous: true)
        assert_includes @org.public_members, @user
      end
    else
      test "does not publicize org memberships" do
        OrganizationOrchestration.add_users(actor: @owner, organizations: [@business_org], teams: [], users: [@user], business_id: @business.id).execute(synchronous: true)
        refute_includes @org.public_members, @user
      end
    end
  end

  context "step admin_added_email" do
    test "does not send admin added email if action is not admin" do
      OrganizationMailer.expects(:admin_added).never
      OrganizationOrchestration.add_users(actor: @owner, organizations: [@org], teams: [], users: [@user]).execute(synchronous: true)
    end

    test "sends admin added email for each user" do
      OrganizationMailer.expects(:admin_added).returns(stub(deliver_later: nil))
      OrganizationOrchestration.add_users(actor: @owner, action: "admin", organizations: [@org], teams: [], users: [@user]).execute(synchronous: true)
    end
  end

  context "step synchronize_user_search_index" do
    test "calls synchronize_user_search_index for each user" do
      User.any_instance.expects(:synchronize_search_index)
      OrganizationOrchestration.add_users(actor: @owner, action: "admin", organizations: [@org], teams: [], users: [@user]).execute(synchronous: true)
    end
  end

  context "step clear_user_contribution_caches" do
    test "calls bulk_clear_caches_for_users" do
      Contribution.expects(:bulk_clear_caches_for_users)
      OrganizationOrchestration.add_users(actor: @owner, action: "admin", organizations: [@org], teams: [], users: [@user]).execute(synchronous: true)
    end
  end

  context "step mailchimp_team_list_update" do
    unless GitHub.single_business_environment?
      test "enqueues MailchimpTeamListJob" do
        assert_enqueued_with(job: MailchimpTeamListJob) do
          OrganizationOrchestration.add_users(actor: @owner, action: "admin", organizations: [@org], teams: [], users: [@user]).execute(synchronous: true)
        end
      end
    end
  end

  context "step update_integration_installation_rate_limits" do
    test "enqueues UpdateIntegrationInstallationRateLimitJob" do
      installation = make_integration_installation(target: @org)
      assert_enqueued_with(job: UpdateIntegrationInstallationRateLimitJob) do
        OrganizationOrchestration.add_users(actor: @owner, action: "admin", organizations: [@org], teams: [], users: [@user]).execute(synchronous: true)
      end
    end
  end

  context "step instrument_add_members" do
    test "skip step" do
      GlobalInstrumenter.stubs(:instrument).with("user_contribution_history.modified", anything)
      GlobalInstrumenter.expects(:instrument).with("org.add_member", anything).never
      OrganizationOrchestration.add_users(actor: @owner, action: "admin", organizations: [@org], teams: [], users: [@user], perform_instrumentation: false).execute(synchronous: true)
    end

    test "instruments org.add_member" do
      GlobalInstrumenter.stubs(:instrument).with("user_contribution_history.modified", anything)
      GlobalInstrumenter.expects(:instrument).with("org.add_member", anything).once
      OrganizationOrchestration.add_users(actor: @owner, action: "admin", organizations: [@org], teams: [], users: [@user], perform_instrumentation: true).execute(synchronous: true)
    end
  end

  context "step add_organization_membership_entry" do
    unless GitHub.single_business_environment?
      test "adds organization membership entry for users" do
        OrganizationOrchestration.add_users(actor: @emu_owner, action: "admin", organizations: [@emu_org], teams: [], users: [@emu], perform_instrumentation: true).execute(synchronous: true)
        refute_nil OrganizationMembershipEntry.where(user_id: @emu.id, organization_id: @emu_org.id).first
      end
    end
  end

  context "step set_enterprise_cloud_trial" do
    test "enqueues EnterpriseCloudTrialNoticeForNewMembersJob" do
      business_plus_org = create(:organization, plan: GitHub::Plan.business_plus)
      assert_enqueued_with(job: EnterpriseCloudTrialNoticeForNewMembersJob) do
        OrganizationOrchestration.add_users(actor: business_plus_org.admins.first, action: "admin", organizations: [business_plus_org], teams: [], users: [@user]).execute(synchronous: true)
      end
    end
  end
end
