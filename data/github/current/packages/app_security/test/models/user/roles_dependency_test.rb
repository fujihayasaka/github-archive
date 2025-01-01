# typed: true
# frozen_string_literal: true

require "test_helper"

class UserRolesDependencyTest < GitHub::TestCase
  include GitHub::UserTestHelpers
  include AuditLog::IntegrationTestHelpers
  include InstrumentationHelper
  include UnlockedRepositoryCheckTestHelper

  fixtures do
    @staffer            = create(:staff_admin_user)
    @unlocker           = create(:staff_admin_user, stafftools_roles: ["can-unlock-repos-with-owners-permission"])
    @super_unlocker     = create(:staff_admin_user, stafftools_roles: ["can-unlock-repos-without-owners-permission"])
    @employee           = preview_user
    @non_staff_user     = create(:user, login: "user", plan: "medium")
    @non_staff_user2    = create(:user, login: "user2", plan: "medium")
    @repo               = create(:private_repository, :minimal, name: "trestles", owner: @non_staff_user)
    @repo2              = create(:private_repository, :minimal, name: "tracks", owner: @non_staff_user)
    @reason             = "because I said so"

    @org = create :business_plus_organization
    @org_repo = create :private_repository, :minimal, owner: @org
    @custom_role = create(:custom_repository_role, name: "custom repo role", owner_id: @org.id, base_role_id: Role.write_role.id)

    if GitHub.enterprise?
      business = create(:global_business)
      business_security_manager_team = create(:enterprise_security_manager_team, business:)
      @enterprise_security_manager = create(:user, business:)
      business_security_manager_team.bulk_add_members(users: [@enterprise_security_manager])
    else
      # EMU business for testing
      @emu_business = create(:business, :enterprise_managed)
      @emu_owner = @emu_business.find_first_emu_owner
      emu_business_security_manager_team = create(:enterprise_security_manager_team, business: @emu_business)
      @enterprise_security_manager = create(:emu, business: @emu_business)
      emu_business_security_manager_team.bulk_add_members(users: [@enterprise_security_manager])
      @emu_user = create(:emu, business: @emu_business)
      @emu_owned_repo = create(:private_repository, owner: @emu_user, force_user_owned: true)
      @emu_org = create(:organization, business: @emu_business)
      @emu_org_repo = create(:repository, owner: @emu_org)

      # Non-emu business for testing
      @non_emu_owner = create :user, login: "non-emu-owner"
      @non_emu_business = create :business, owners: [@non_emu_owner]
      @non_emu_org = create(:organization, business: @non_emu_business)
      @non_emu_user = create :user, login: "non-emu-user"
      @non_emu_org.add_member(@non_emu_user)
      @non_emu_user_repo = create(:repository, owner: @non_emu_user)
    end
  end

  setup do
    clear_memoized_unlocked_repository_check
  end

  context "#async_batch_action_and_role_level_for" do
    test "returns admin" do
      action_and_role_promise = @non_staff_user.async_batch_action_and_role_level_for(@repo)
      action_and_role = action_and_role_promise.sync
      assert_equal %w[admin admin], action_and_role
    end

    test "returns maintain role" do
      @org_repo.add_member(@non_staff_user2, action: :maintain)
      action_and_role_promise = @non_staff_user2.async_batch_action_and_role_level_for(@org_repo)
      action_and_role = action_and_role_promise.sync
      assert_equal %w[maintain maintain], action_and_role
    end

    test "returns custom role" do
      @org_repo.add_member(@non_staff_user2, action: @custom_role.name)
      action_and_role_promise = @non_staff_user2.async_batch_action_and_role_level_for(@org_repo)
      action_and_role = action_and_role_promise.sync
      assert_equal [@custom_role.base_role.name, @custom_role.name], action_and_role
    end

    test "returns base role of all repo
     role" do
      @org.add_member(@non_staff_user2)
      assert @org.grant_org_role(assignee: @non_staff_user2, role: OrganizationRole.all_repo_maintain_role).success?
      action_and_role_promise = @non_staff_user2.async_batch_action_and_role_level_for(@org_repo)
      action_and_role = action_and_role_promise.sync

      assert_equal [OrganizationRole.all_repo_maintain_role.base_role.name, OrganizationRole.all_repo_maintain_role.base_role.name], action_and_role
    end

    test "batches queries" do
      _, queries_single = log_cleaned_queries do
        @non_staff_user.async_batch_action_and_role_level_for(@repo).sync
      end

      _, queries_multiple = log_cleaned_queries do
        promises = []
        promises << @non_staff_user.async_batch_action_and_role_level_for(@repo2)
        promises << @non_staff_user2.async_batch_action_and_role_level_for(@repo2)
        Promise.all(promises).sync
      end

      assert_equal queries_single.count, queries_multiple.count
    end
  end

  context "#unlock_repository" do
    if GitHub.enterprise?
      test "does not require an active grant in Enterprise" do
        unlock = @unlocker.unlock_repository(@repo, @reason)
        assert unlock.valid?
      end
    else
      test "returns false if a relevant StaffAccessGrant does not exist" do
        refute @unlocker.unlock_repository(@repo)
      end
    end

    test "when access is allowed, creates a RepositoryUnlock object and returns true on success" do
      create :staff_access_grant, accessible: @repo, granted_by: @repo.owner
      assert @unlocker.unlock_repository(@repo)

      unlock = RepositoryUnlock.find_by(repository_id: @repo.id)
      assert_equal @repo, unlock&.repository
    end

    test "does not notify repo owner when unlock created by staff" do
      EnterpriseMailer.expects(:user_repository_unlocked).never

      create :staff_access_grant, accessible: @repo, granted_by: @repo.owner
      @unlocker.unlock_repository(@repo)
    end

    test "works for an EMU owner on an EMU user-owned repo", skip_enterprise: true do
      unlock = @emu_owner.unlock_repository(@emu_owned_repo, "Totally legit reason")
      assert unlock.valid?
    end

    test "works for an enterprise security manager on a user-owned enterprise repo" do
      repo = GitHub.enterprise? ? @repo : @emu_owned_repo

      unlock = @enterprise_security_manager.unlock_repository(repo, "Totally legit reason")
      assert unlock.valid?
    end

    test "creates an audit log entry when EMU owner unlocks user owned repo", skip_enterprise: true do
      events = assert_performed_audit_entries(count: 1, only: "repo.temporary_access_granted") do
        @emu_owner.unlock_repository(@emu_owned_repo, "Enterprise user enabled temporary access to user-owned repo")
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        reason: "Enterprise user enabled temporary access to user-owned repo",
        actor: @emu_owner.login,
        actor_id: @emu_owner.id,
        user: @emu_user.login,
        user_id: @emu_user.id,
        repo: @emu_owned_repo.name_with_owner,
        repo_id: @emu_owned_repo.id,
        business: @emu_business.name,
        business_id: @emu_business.id
      }

      assert_subset_hash expected_payload, events.first
    end

    test "creates a notification when EMU owner unlocks an EMU user-owned repo", skip_enterprise: true do
      EnterpriseMailer.expects(:user_repository_unlocked).once.returns(stub(deliver_later: nil))

      tmp_events = subscribe "repo.temporary_access_granted"
      @emu_owner.unlock_repository(@emu_owned_repo, "EMU admin enabled temporary access to user-owned repo")

      assert_equal 1, tmp_events.length
      refute_nil event = tmp_events.pop

      expected_reason = "Enterprise user enabled temporary access to user-owned repo"
      assert_equal(
        {
          reason: expected_reason,
          user: @emu_user.display_login,
          user_id: @emu_user.id,
          actor: @emu_owner.display_login,
          actor_id: @emu_owner.id,
          repo: @emu_owned_repo.full_name,
          repo_id: @emu_owned_repo.id,
          public_repo: false,
        },
        event.payload,
      )
    end

    test "does not create an audit log entry when EMU owner unlocks an EMU user-owned repo", enterprise_only: true do
      EnterpriseMailer.expects(:user_repository_unlocked).never

      tmp_events = subscribe "repo.temporary_access_granted"
      @unlocker.unlock_repository(@repo, "EMU admin unlocking EMU owned repo")
      assert_equal 0, tmp_events.length
    end

    test "creates a notification when enterprise security manager unlocks an EMU user-owned repo" do
      if GitHub.enterprise?
        EnterpriseMailer.expects(:user_repository_unlocked).never
      else
        EnterpriseMailer.expects(:user_repository_unlocked).once.returns(stub(deliver_later: nil))
      end

      tmp_events = subscribe "repo.temporary_access_granted"

      repo = GitHub.enterprise? ? @repo : @emu_owned_repo
      @enterprise_security_manager.unlock_repository(repo, "EMU user enabled temporary access to user-owned repo")

      assert_equal 1, tmp_events.length
      refute_nil event = tmp_events.pop
      assert_equal "repo.temporary_access_granted", event.name

      expected_reason = "#{GitHub.enterprise? ? "EMU" : "Enterprise"} user enabled temporary access to user-owned repo"
      assert_equal(
        {
          reason: expected_reason,
          user: repo.owner.display_login,
          user_id: repo.owner.id,
          actor: @enterprise_security_manager.display_login,
          actor_id: @enterprise_security_manager.id,
          repo: repo.nwo,
          repo_id: repo.id,
          public_repo: false,
        },
        event.payload,
      )
    end
  end

  context "can_unlock_user_repo?" do
    test "false for EMU users unlocking their own repos", skip_enterprise: true do
      refute @emu_user.can_unlock_user_repo?(repository: @emu_owned_repo)
    end

    test "false for non EMU businesses", skip_enterprise: true do
      refute @non_emu_owner.can_unlock_user_repo?(repository: @non_emu_user_repo)
    end

    context "for EMU admin", skip_enterprise: true do
      test "true when unlocking EMU user-owned repo" do
        assert @emu_owner.can_unlock_user_repo?(repository: @emu_owned_repo)
      end

      test "false when unlocking rando repo" do
        refute @emu_owner.can_unlock_user_repo?(repository: @repo)
      end

      test "false for unlocking org owned repos" do
        refute @emu_owner.can_unlock_user_repo?(repository: @emu_org_repo)
      end
    end

    context "for enterprise security manager" do
      test "true when unlocking user-owned enterprise repo" do
        repo = GitHub.enterprise? ? @repo : @emu_owned_repo

        assert @enterprise_security_manager.can_unlock_user_repo?(repository: repo)
      end

      test "false for unlocking rando repo", skip_enterprise: true do
        refute @enterprise_security_manager.can_unlock_user_repo?(repository: @repo)
      end

      test "false when unlocking org owned repos" do
        repo = GitHub.enterprise? ? @org_repo : @emu_org_repo

        refute @enterprise_security_manager.can_unlock_user_repo?(repository: repo)
      end
    end
  end

  context "#has_unlocked_repository?" do
    test "a repo can be checked to see if it has an active unlock" do
      refute @unlocker.has_unlocked_repository?(@repo)

      create :staff_access_grant, accessible: @repo, granted_by: @repo.owner
      assert @unlocker.unlock_repository(@repo)
      clear_memoized_unlocked_repository_check

      assert @unlocker.has_unlocked_repository?(@repo)
    end

    test "the unlocked check returns false if a staff grant has been given but the repo is not unlocked" do
      create :staff_access_grant, accessible: @repo, granted_by: @repo.owner
      refute @unlocker.has_unlocked_repository?(@repo)
    end

    test "the unlocked check returns false if a staff grant has not been given" do
      refute @unlocker.has_unlocked_repository?(@repo)
    end

    unless GitHub.enterprise?
      test "the unlocked check returns false if the associated StaffAccessGrant has been revoked" do
        refute @unlocker.has_unlocked_repository?(@repo)

        grant = create :staff_access_grant, accessible: @repo, granted_by: @repo.owner
        assert @unlocker.unlock_repository(@repo)
        clear_memoized_unlocked_repository_check
        assert @unlocker.has_unlocked_repository?(@repo)

        grant.revoke(@non_staff_user)
        @unlocker.reload
        clear_memoized_unlocked_repository_check

        refute @unlocker.has_unlocked_repository?(@repo)
      end
    end

    test "the unlocked check returns false immediately if the user is not staff" do
      refute @non_staff_user.has_unlocked_repository?(@repo)

      create :staff_access_grant, accessible: @repo, granted_by: @repo.owner
      assert @unlocker.unlock_repository(@repo)
      clear_memoized_unlocked_repository_check

      assert @unlocker.has_unlocked_repository?(@repo)
      refute @non_staff_user.has_unlocked_repository?(@repo)
    end

    test "the unlocked check returns false if the repo had been unlocked, but the lock has expired" do
      refute @unlocker.has_unlocked_repository?(@repo)

      create :staff_access_grant, accessible: @repo, granted_by: @repo.owner
      lock = @unlocker.unlock_repository(@repo)
      clear_memoized_unlocked_repository_check
      assert @unlocker.has_unlocked_repository?(@repo)

      lock.update(expires_at: 7.hours.ago)
      @unlocker.reload
      clear_memoized_unlocked_repository_check

      # should not be unlocked after 7 hours
      refute @unlocker.has_unlocked_repository?(@repo)
    end

    test "has_unlocked_repository? memoizes false results" do
      assert_operator count_queries { refute @unlocker.has_unlocked_repository?(@repo) }, :>, 0

      assert_query_count(0) do
        refute @unlocker.has_unlocked_repository?(@repo)
      end
    end

    test "has_unlocked_repository? memoizes true results" do
      create :staff_access_grant, accessible: @repo, granted_by: @repo.owner
      assert @unlocker.unlock_repository(@repo)

      assert_operator count_queries { assert @unlocker.has_unlocked_repository?(@repo) }, :>, 0

      assert_query_count(0) do
        assert @unlocker.has_unlocked_repository?(@repo)
      end
    end

    test "unlock_repository resets memoization for that repo" do
      assert_operator(
        count_queries do
          refute @unlocker.has_unlocked_repository?(@repo)
          refute @unlocker.has_unlocked_repository?(@repo2)
        end, :>, 0
      )

      assert_query_count(0) do
        refute @unlocker.has_unlocked_repository?(@repo)
        refute @unlocker.has_unlocked_repository?(@repo2)
      end

      create :staff_access_grant, accessible: @repo, granted_by: @repo.owner
      assert @unlocker.unlock_repository(@repo)
      clear_memoized_unlocked_repository_check

      assert_operator count_queries { assert @unlocker.has_unlocked_repository?(@repo) }, :>, 0

      assert_query_count(0) do
        assert @unlocker.has_unlocked_repository?(@repo)
        refute @unlocker.has_unlocked_repository?(@repo2)
      end
    end


    test "reload resets memoization for all repos" do
      assert_operator(
        count_queries do
          refute @unlocker.has_unlocked_repository?(@repo)
          refute @unlocker.has_unlocked_repository?(@repo2)
        end, :>, 0
      )

      assert_query_count(0) do
        refute @unlocker.has_unlocked_repository?(@repo)
        refute @unlocker.has_unlocked_repository?(@repo2)
      end

      @unlocker.reload
      clear_memoized_unlocked_repository_check

      assert_operator(
        count_queries do
          refute @unlocker.has_unlocked_repository?(@repo)
          refute @unlocker.has_unlocked_repository?(@repo2)
        end, :>, 0
      )

      assert_query_count(0) do
        refute @unlocker.has_unlocked_repository?(@repo)
        refute @unlocker.has_unlocked_repository?(@repo2)
      end
    end
  end

  context "#can_fake_login?" do
    if GitHub.enterprise?
      context "in enterprise" do
        test "returns true for site admins" do
          assert @staffer.can_fake_login?
        end

        test "returns false if user is not site admin" do
          refute @employee.can_fake_login?
        end
      end
    else
      test "returns false if user is not site admin" do
        refute @employee.can_fake_login?
      end

      test "returns false when user does not have sufficient stafftools role" do
        refute @staffer.can_fake_login?
      end

      test "returns true when user has sufficient stafftools role" do
        impersonator = create(:staff_admin_user, stafftools_roles: ["can-impersonate-users"])
        assert impersonator.can_fake_login?
      end
    end
  end

  context "#can_unlock_repos?" do
    if GitHub.enterprise?
      context "in enterprise" do
        test "returns true for site admins" do
          assert @staffer.can_unlock_repos?
        end

        test "returns false if user is not site admin" do
          refute @employee.can_unlock_repos?
        end
      end
    else
      test "returns false if user is not site admin" do
        refute @employee.can_unlock_repos?
      end

      test "returns false when user does not have sufficient stafftools role" do
        refute @staffer.can_unlock_repos?
      end

      test "returns true when user has sufficient stafftools role" do
        assert @unlocker.can_unlock_repos?
      end
    end
  end

  unless GitHub.enterprise?
    context "#can_unlock_repos_without_owners_permission?" do
      test "returns false if user is not site admin" do
        refute @employee.can_unlock_repos_without_owners_permission?
      end

      test "returns false when user does not have sufficient stafftools role" do
        refute @unlocker.can_unlock_repos_without_owners_permission?
      end

      test "returns true when user has sufficient stafftools role" do
        assert @super_unlocker.can_unlock_repos_without_owners_permission?
      end
    end
  end

  context "#employee?" do
    test "site_admin? is true for site admins" do
      assert @staffer.site_admin?
    end

    test "site_admin? isn't true for employees" do
      refute @employee.site_admin?
    end

    test "site_admin? isn't true for regular users" do
      refute @non_staff_user.site_admin?
    end

    test "employees can be made site admins" do
      @employee.grant_site_admin_access "just playin"
      assert @employee.site_admin?
    end

    test "employee? is true for employees on dotcom" do
      if GitHub.enterprise?
        refute @employee.employee?
      else
        assert @employee.employee?
      end
    end

    unless GitHub.enterprise?
      test "non-employees cannot manually be made site admins (staff)" do
        refute @non_staff_user.site_admin?
        assert_raises ArgumentError do
          @non_staff_user.update_attribute(:gh_role, "staff")
        end
      end

      test "non-employees cannot be made site admins (staff)" do
        user = User.new
        user.gh_role = "staff"
        refute user.valid?
        assert user.errors.full_messages.include?("Gh role staff must also be on the employees team. If this is you, try toggling staff mode with the ` key.")
      end

      test "validation does not fail staff_must_be_an_employee check if in disabled employee mode" do
        user = create(:user, :staff)
        user.disable_employee_mode

        user.last_ip = "0.0.0.0"
        assert user.valid?
      end

      test "update_attributes does not fail staff_must_be_an_employee check if in disabled employee mode" do
        user = create(:user, :staff)
        user.disable_employee_mode

        # This would raise if the check wasn't conditional on changing gh_role.
        user.update_attribute(:last_ip, "0.0.0.0")
      end
    end

    # In 2017 we changed site admins to have to be employees for !enterprise.
    test "employee? is appropriate for site admins" do
      if GitHub.enterprise?
        refute @staffer.employee?
      else
        assert @staffer.employee?
      end
    end

    test "employee? isn't true for regular users" do
      refute @non_staff_user.employee?
    end
  end

  context "#revoke_new_hire_accesses" do
    test "doesn't revoke third-party integrations" do
      user = create :user
      personal_access_token = create :personal_token_oauth_access, user: user
      third_party_application = create :oauth_application, user: user
      third_party_access = create :oauth_access, user: user, application: third_party_application

      user.revoke_new_hire_accesses
      perform_enqueued_jobs(only: [RemoveOauthUserTokensJob])
      refute OauthAccess.exists?(personal_access_token.id)
      assert OauthAccess.exists?(third_party_access.id)
    end
  end
end
