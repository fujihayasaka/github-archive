# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.single_business_environment?
  # We are not able to remove users from a business in a single business
  # environment
else
  class BusinessMemberDestroyerTest < GitHub::TestCase
    include AuditLog::IntegrationTestHelpers

    fixtures do
      @business = create(:business)
      @org = create(:organization, business: @business)
      @admin = @org.admins.first
      @admin.update(login: "org-admin")

      @first_member = create(:user, login: "user")
      @org.add_member(@first_member)

      @owner = @business.owners[0]
    end

    setup do
      @destroyer = Business::MemberDestroyer.new(@business, @owner)
    end

    context "#destroy" do
      test "raises NoMethodError if passed nil" do
        assert_raises(::NoMethodError) { @destroyer.destroy(nil) }
      end

      test "removes the user from the enterprise and from all orgs", skip_enterprise: true do
        assert_includes @business.user_accounts, @first_member.business_user_account
        assert_includes @org.members, @first_member

        perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob, RemoveOrgMemberJob]) do
          @destroyer.destroy(@first_member)
        end

        refute_includes @business.user_accounts, @first_member.business_user_account
        refute_includes @org.members, @first_member
      end

      test "removes user from enterprise teams" do
        assert_includes @org.members, @admin
        assert_includes @business.user_accounts, @admin.business_user_account

        enterprise_team = create :enterprise_team, business: @business, sync_to_organizations: "all"
        org_team = create :team, organization: @org
        EnterpriseTeamOrganizationMapping.create(enterprise_team: enterprise_team, organization: @org, team: org_team)
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

        perform_enqueued_jobs(only: [RemoveOrgAdminJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, EnterpriseTeamOrganizationReconciliationJob]) do
          EnterpriseTeamOrganizationReconciliationJob.perform_now(enterprise_team_id: enterprise_team.id)
          RemoveBusinessMemberJob.perform_now(@business.id, @owner.id, @admin.id, {})
        end

        @org.reload
        refute_includes @org.members, @admin
        refute_includes @business.user_accounts, @admin.business_user_account
        assert_includes @org.members, @owner
        refute_includes enterprise_team.member_user_ids, @admin.id
      end

      test "enterprise admin tries to remove the last org admin results in adding the enterprise admin to the org and removing the org admin" do
        assert_equal @org.admins, [@admin]
        assert_equal @org.members.length, 2
        assert_includes @org.members, @first_member

        perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob, RemoveOrgAdminJob, RemoveOrgMemberJob]) do
          @destroyer.destroy(@admin)
        end

        assert_equal @org.admins, [@owner]
        assert_equal @org.members.length, 2
        assert_includes @org.members, @first_member
      end

      test "only organizations associated with the enterprise are affected by an enterprise owner removing a member" do
        # Organizations to which the member belongs that are not associated with the enterprise are not affected
        @outside_org = create(:organization, login: "outside-org", admin: @admin)
        assert_equal @org.admins, [@admin]
        assert_equal @org.members.length, 2
        assert_includes @org.members, @first_member
        assert_equal @outside_org.admins, [@admin]
        assert_nil @outside_org.business

        perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob, RemoveOrgAdminJob, RemoveOrgMemberJob]) do
          @destroyer.destroy(@admin)
        end

        @outside_org.reload

        assert_equal @org.admins, [@owner]
        assert_equal @org.members.length, 2
        assert_includes @org.members, @first_member
        assert_equal @outside_org.admins, [@admin]
      end

      test "enterprise admin removes an org owner and due to a race condition, remove_member fails" do
        refute_equal @admin, @destroyer.actor # making sure the actor is different to ensure the correct code path is followed
        assert_equal @org.admins, [@admin]
        assert_equal @org.members.length, 2
        assert_includes @org.members, @first_member

        # By stubbing organizations#add_admin to do nothing,
        # we simulate a race condition where other actions outside
        # of this code path resulted in `@business.remove_member(member, actor:
        # @actor` attempting to remove the last admin of an organization
        Organization.any_instance.stubs(:add_admin).returns(nil)

        assert_raises Organization::NoAdminsError do
          @destroyer.destroy(@admin)
        end
      end

      test "business owner removes a fellow business owner and due to a race condition, actor gets removed from business before the job is completed, leading to remove_member failing" do
        # simulate race condition where Business#remove_member will think the member we're trying to remove is the last owner of the business.
        Business.any_instance.stubs(:owners).returns([@admin])

        assert_raises Business::NoAdminsError do
          @destroyer.destroy(@admin)
        end
      end

      test "verifies that the audit log reason is captured (along with other relevant audit log info)" do
        events = assert_performed_audit_entries(count: 1, only: "business.remove_member") do
          @destroyer.destroy(@admin)
        end

        assert_equal last_performed_audit_entries, events
        expected_payload = {
          name: @business.name,
          reason: "#{@owner.login} is removing #{@admin.login} via the web interface.",
          business: @business.slug,
          business_id: @business.id,
          user: @admin.login,
          user_id: @admin.id,
          actor: @owner.login,
          actor_id: @owner.id,
        }
        assert_subset_hash expected_payload, events.first
      end

      test "fails early with a helpful message if the actor and the member are the same user, and that user is the last owner of any orgs in the business" do
        # We should only get in this predicament if there's a race condition
        # since there are checks at the controller level to prevent this situation
        # from happening
        second_business_owner = create :user
        @business.add_owner(second_business_owner, actor: @owner)
        second_org = create :organization, business: @business, admins: [@owner]
        assert @business.owners.count > 1
        assert_equal second_org.admins.count, 1

        assert_raises_with_message(Organization::NoAdminsError, "User #{@owner.display_login} is the last admin in these organizations: #{second_org.display_login}") do
          @destroyer.destroy(@owner)
        end

        assert_includes @business.owners, @owner
      end

    end
  end
end
