# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class RepositorySetVisibilityTest < GitHub::TestCase
  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

    @mojombo  = create(:user, login: "mojombo2", plan: "pro")
    @defunkt  = create(:credit_card_user, login: "defunkt",  plan: "pro")
    @pj       = create(:user, login: "pj",       plan: "pro")
    @maddox   = create(:user, login: "maddox")
    @rtomayko = create(:user, login: "rtomayko", plan: "pro")

    @grit     = create :repository, name: "grit", owner: @mojombo, from_example: :mojombo_grit
    @ambition = create :private_repository, name: "ambition", owner: @defunkt, from_example: :defunkt_ambition
    @simple   = create :repository, name: "simple", owner: @rtomayko, from_example: :simple

    @biz_org_admin = create(:user)
    @biz_org = create(:organization, plan: GitHub::Plan.business_plus, admins: [@biz_org_admin, @rtomayko], seats: 20)
    if GitHub.single_business_environment?
      @business = Business.first
    else
      @business = create(:business, name: "Ian, Inc", owners: [@biz_org_admin], organizations: [@biz_org], seats: 20)
    end
    @biz_org.update!(business: @business)
    @biz_org.allow_private_repository_forking(actor: @biz_org_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

    @biz_grit     = create(:repository, name: "biz-grit",     owner: @biz_org, from_example: :mojombo_grit)
    @biz_ambition = create(:private_repository, name: "biz-ambition", owner: @biz_org, from_example: :defunkt_ambition)
    @biz_simple   = create(:repository, name: "biz-simple",   owner: @biz_org, from_example: :repository_test_simple)

    @biz_internal_ambition = create(:internal_repository, name: "biz-internal-ambition", owner: @biz_org, from_example: :defunkt_ambition)

    example_repo_snapshot(snapshot_spokesdb: true)
  end

  setup do
    example_repo_restore
  end

  context "#can_change_repo_visibility?" do
    if GitHub.single_business_environment?
      # With "Repository visibility change" policy unset
      test "returns true for org admin when enterprise repository visibility change policy is unset" do
        assert @biz_grit.can_change_repo_visibility?(@biz_org_admin)
      end

      test "returns true for org member with repo admin when enterprise repository visibility change policy is unset" do
        member = create :user
        @biz_org.add_member member
        @biz_grit.add_member member, action: :admin
        assert @biz_grit.can_change_repo_visibility?(member)
      end

      # With "Repository visibility change" policy "Enabled"
      test "returns true for org admin when enterprise repository visibility change policy is enabled" do
        @business.allow_members_to_change_repo_visibility(actor: @biz_org_admin, force: true)
        assert @biz_grit.can_change_repo_visibility?(@biz_org_admin)
      end

      test "returns true for org member with repo admin when enterprise repository visibility change policy is enabled" do
        member = create :user
        @biz_org.add_member member
        @biz_grit.add_member member, action: :admin
        @business.allow_members_to_change_repo_visibility(actor: @biz_org_admin, force: true)
        assert @biz_grit.can_change_repo_visibility?(member)
      end

      # With "Repository visibility change" policy "Disabled"
      test "returns true for org admin when enterprise repository visibility change policy is disabled" do
        @business.block_members_from_changing_repo_visibility(actor: @biz_org_admin, force: true)
        assert @biz_grit.can_change_repo_visibility?(@biz_org_admin)
      end

      test "returns false for org member with repo admin when enterprise repository visibility change policy is disabled" do
        member = create :user
        @biz_org.add_member member
        @biz_grit.add_member member, action: :admin
        @business.block_members_from_changing_repo_visibility(actor: @biz_org_admin, force: true)
        refute @biz_grit.can_change_repo_visibility?(member)
      end
    end

    test "returns true for site admins on enterprise", enterprise_only: true do
      site_admin = create :staff_admin_user
      @business.block_members_from_changing_repo_visibility(actor: @biz_org_admin, force: true)
      assert @biz_grit.can_change_repo_visibility?(site_admin)
    end

    test "returns false for site admins who are not org admins on dotcom", skip_enterprise: true do
      site_admin = create :staff_admin_user
      @business.block_members_from_changing_repo_visibility(actor: @biz_org_admin, force: true)
      refute @biz_grit.can_change_repo_visibility?(site_admin)
    end
  end

  context "Setting the visibility of a public repo to private" do
    test "makes members collaborators" do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @simple.owner.stubs(:at_private_repo_limit?).returns(false)
        @simple.set_visibility(actor: @simple.owner, visibility: "private")
        @simple.reload
        assert_predicate @simple, :private?
        @simple.add_member(@pj)

        assert_difference "@simple.owner.reload.collaborators_count", -1 do
          @simple.set_visibility(actor: @simple.owner, visibility: "public")
        end
      end
    end

    test "succeeds if repository has trade restricted invitees" do
      invitation = create :repository_invitation, repository: @simple
      invitee = invitation.invitee
      invitee.trade_controls_restriction.full!

      assert_predicate invitee, :has_any_trade_restrictions?
      assert_equal 1, @simple.invitees.count

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @simple.set_visibility(actor: @simple.owner, visibility: "private") }
      assert_predicate @simple.reload, :private?
    end

    test "succeeds if repostiory has trade restricted collaborators" do
      user = create :user
      @simple.add_member(user)
      user.trade_controls_restriction.full!
      assert_predicate user, :has_any_trade_restrictions?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @simple.set_visibility(actor: @simple.owner, visibility: "private") }
      assert_predicate @simple.reload, :private?
    end

    test "fails if repository is read only based on ownership by a trade controls restricted org" do
      org = create :organization
      repo = create :repository, owner: org
      org.trade_controls_restriction.full!
      assert_predicate org, :has_any_trade_restrictions?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: org.admin, visibility: "private") }
      repo.reload
      refute_predicate org, :private?
      assert_match /can't be private. We are unable to provide this feature/, repo.errors[:visibility].first
    end

    test "fails if repository owned by a partial trade controls restricted org" do
      org = create :organization
      repo = create :repository, owner: org
      org.trade_controls_restriction.partial!
      assert_predicate org, :has_partial_trade_restrictions?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: org.admin, visibility: "private") }

      refute_predicate repo.reload, :private?
      assert_match /can't be private. We are unable to provide this feature/, repo.errors[:visibility].first
    end

    test "fails if repository owned by a tier_1 trade controls restricted org" do
      org = create :organization, plan: "free"
      repo = create :repository, owner: org
      org.trade_controls_restriction.tier_1!
      assert_predicate org, :has_tier_1_trade_restrictions?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: org.admin, visibility: "private") }

      refute_predicate repo.reload, :private?
      assert_match /can't be private. We are unable to provide this feature/, repo.errors[:visibility].first
    end

    test "fails if actor is trade controls restricted, even if owner is not" do
      org   = create :organization
      repo  = create :repository, owner: org
      admin = org.admin
      admin.trade_controls_restriction.full!
      assert_predicate admin, :has_full_trade_restrictions?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: admin, visibility: "private") }

      refute_predicate repo.reload, :private?
      assert_match /can't be private. We are unable to provide this feature/, repo.errors[:visibility].first
    end

    test "fails if you don't have the quota for it" do
      @simple.owner.expects(:at_private_repo_limit?).returns(true).twice
      assert_predicate @simple, :public?
      refute_predicate @simple, :can_privatize?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @simple.set_visibility(actor: @simple.owner, visibility: "private") }
      assert_predicate @simple.reload, :public?
    end

    test "fails if you're on a per-seat plan and don't have enough seats for it" do
      org = create :organization, plan: "business", seats: 5
      repo = create(:public_repository, owner: org)
      5.times { repo.add_member(create(:user)) }
      if GitHub.enterprise?
        assert_predicate repo, :can_privatize?
      else
        refute_predicate repo, :can_privatize?
      end

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: org.admins.first, visibility: "private") }
      repo.reload

      if GitHub.enterprise?
        assert_predicate repo, :private?
      else
        assert_predicate repo, :public?
      end
    end

    test "fails if you're on a per-seat plan and pending invitation puts org over quota" do
      org = create :organization, plan: "business", seats: 5
      repo = create(:public_repository, owner: org)
      4.times { repo.add_member(create(:user)) }
      create :repository_invitation, repository: repo

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: org.admins.first, visibility: "private") }
      repo.reload

      if GitHub.enterprise?
        assert_predicate repo, :private?
      else
        assert_predicate repo, :public?
        assert repo.errors[:visibility].any?
        assert_match /can't be private. Please add seats/, repo.errors[:visibility].first
      end
    end

    test "fails if you're on a per-seat plan and a pending plan change would mean you don't have enough seats for it" do
      org = create :organization, plan: "business", seats: 6
      repo = create(:public_repository, owner: org)
      5.times { repo.add_member(create(:user)) }
      create(:billing_pending_plan_change, user: org, seats: 5, active_on: 1.month.from_now)

      if GitHub.enterprise?
        assert_predicate repo, :can_privatize?
      else
        refute_predicate repo, :can_privatize?
      end

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: org.admins.first, visibility: "private") }
      repo.reload

      if GitHub.enterprise?
        assert_predicate repo, :private?
      else
        assert_predicate repo, :public?
      end
    end

    test "fails if you're on a per-seat plan and a pending plan change would mean you don't have enough seats for the pending invitation" do
      org = create :organization, plan: "business", seats: 6
      repo = create(:public_repository, owner: org)
      4.times { repo.add_member(create(:user)) }
      create :repository_invitation, repository: repo
      create(:billing_pending_plan_change, user: org, seats: 5, active_on: 1.month.from_now)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: org.admins.first, visibility: "private") }
      repo.reload

      if GitHub.enterprise?
        assert_predicate repo, :private?
      else
        assert_predicate repo, :public?
        assert repo.errors[:visibility].any?
        assert_match /can't be private. Please cancel the pending seat downgrade to ensure there are seats for collaborators to make this repository private/, repo.errors[:visibility].first
      end
    end

    test "works if you're on a per-seat plan and have enough seats for it" do
      org = create :organization, plan: "business", seats: 5
      repo = create(:public_repository, owner: org)
      4.times { repo.add_member(create(:user)) }
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: org.admins.first, visibility: "private") }
      assert_predicate repo.reload, :private?
    end

    test "works if there is only one repo in the network and owner has quota" do
      @simple.owner.expects(:at_private_repo_limit?).returns(false).at_least_once
      assert_predicate @simple, :public?
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @simple.set_visibility(actor: @simple.owner, visibility: "private") }
      assert_predicate @simple.reload, :private?
    end

    test "destroys pages if toggle was successful", skip_enterprise: true do
      disable_feature_flag(:pages_soft_deletion)
      repo = create(:public_repository, owner: @maddox)
      page = create :page, repository: repo

      assert repo.page
      refute_predicate repo, :private?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: @maddox, visibility: "private") }
      repo.reload

      refute repo.page
      assert_predicate repo, :private?
    end

    test "destroys all protected branches rules if toggle was successful", skip_enterprise: true do
      repo = create(:public_repository, owner: @maddox)
      protected_branch = create :protected_branch, repository: repo

      refute_empty repo.protected_branches
      refute_predicate repo, :private?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: @maddox, visibility: "private") }
      repo.reload

      assert_empty repo.protected_branches
      assert_predicate repo, :private?
    end

    test "detaches the repo into a new, private network if the repo is a fork" do
      @fork = create(:fork_repository, forker: @defunkt, fork_repo: @simple)
      @fork.plan_owner.stubs(:at_private_repo_limit?).returns(false)

      assert_predicate @fork, :public?
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @fork.set_visibility(actor: @fork.owner, visibility: "private") }
      @fork.reload
      assert_predicate @fork, :private?
      refute_equal @simple.network, @fork.reload.network
      assert_predicate @fork, :network_root?
    end

    test "if root, detaches into a new network and elects a new root for network" do
      @simple.owner.stubs(:at_private_repo_limit?).returns(false)
      @fork = create(:fork_repository, forker: @defunkt, fork_repo: @simple)
      @fork2 = create(:fork_repository, forker: @pj, fork_repo: @simple)
      assert_predicate @simple, :public?

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @simple.set_visibility(actor: @simple.owner, visibility: "private") }
      @simple.reload
      assert_predicate @simple, :private?
      assert_predicate @fork.reload, :public?
      refute_equal @simple, @fork.network.root
      refute_equal @simple.network, @fork.network
      assert_nil @simple.parent_id
    end

    test "works if the repo is a fork that does not match the source's visibility" do
      Repository.any_instance.stubs(:async_toggle_repository_visibility).returns(true)

      @fork = create(:fork_repository, forker: @defunkt, fork_repo: @simple)
      @fork.plan_owner.stubs(:at_private_repo_limit?).returns(false)

      assert_predicate @fork, :public?
      assert_predicate @fork, :matches_root_visibility?

      # manually change the source repo, now they've diverged
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @simple.set_visibility(actor: @simple.owner, visibility: "private") }
      @simple.reload
      assert_predicate @simple, :private?

      @fork.root.reload
      refute_predicate @fork, :matches_root_visibility?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @fork.set_visibility(actor: @fork.owner, visibility: "private") }
      @fork.reload
      assert_predicate @fork, :private?
      assert_predicate @fork, :matches_root_visibility?
    end

    test "works for a fork when the plan_owner is at their private repo limit" do
      Repository.any_instance.stubs(:async_toggle_repository_visibility).returns(true)

      @fork = create(:fork_repository, forker: @defunkt, fork_repo: @simple)

      assert_predicate @fork, :public?
      assert_predicate @fork, :matches_root_visibility?
      # manually change the source repo, now they've diverged
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @simple.set_visibility(actor: @simple.owner, visibility: "private") }
      @simple.reload
      assert_predicate @simple, :private?
      @fork.plan_owner.stubs(:at_private_repo_limit?).returns(true)

      @fork.root.reload
      refute_predicate @fork, :matches_root_visibility?

      @fork.owner.stubs(:at_private_repo_limit?).returns(false)
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @fork.set_visibility(actor: @fork.owner, visibility: "private") }
      @fork.reload
      assert_predicate @fork, :private?
      assert_predicate @fork, :matches_root_visibility?
    end

    test "triggers a 'repository.access' instrumentation event" do
      GitHub.context.push(actor_id: @simple.owner.id)
      events = subscribe "repo.access"
      expected_payload = {
        user: @simple.owner.login,
        user_id: @simple.owner.id,
        repo: @simple.name_with_owner,
        repo_id: @simple.id,
        public_repo: !@simple.public?,
        fork_source: @simple.root.name_with_owner,
        fork_source_id: @simple.root.id,
        access: :private,
        visibility: :private,
        previous_visibility: @simple.visibility,
        actor_id: @simple.owner.id,
        actor: @simple.owner.login,
      }

      assert_predicate @simple, :public?
      @simple.owner.stubs(:at_private_repo_limit?).returns(false)
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @simple.set_visibility(actor: @simple.owner, visibility: "private") }
      @simple.reload
      assert_predicate @simple, :private?

      assert event = events.pop, "expected an event to be triggered"
      assert_equal expected_payload, event.payload
    end

    test "does not create a PublicEvent" do
      GitHub.reset_stratocaster

      assert_predicate @simple, :public?
      @simple.owner.stubs(:at_private_repo_limit?).returns(false)
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @simple.set_visibility(actor: @simple.owner, visibility: "private") }
      @simple.reload
      assert_predicate @simple, :private?

      assert_nil GitHub.stratocaster_store.last
    end

    test "does not disable network alternates" do
      @grit.enable_or_disable_shared_storage
      assert_predicate @grit, :shared_storage_enabled?
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @grit.set_visibility(actor: @grit.owner, visibility: "private") }
      @grit.reload
      assert_predicate @grit, :shared_storage_enabled?
    end

    test "disables anonymous git access" do
      GitHub.stubs(:anonymous_git_access_enabled?).returns(true)

      @simple.enable_anonymous_git_access(@simple.owner)
      assert @simple.config.enabled?(Configurable::AnonymousGitAccess::KEY)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @simple.set_visibility(actor: @simple.owner, visibility: "private") }
      @simple.reload
      refute @simple.config.enabled?(Configurable::AnonymousGitAccess::KEY)
    end

    test "unlocks anonymous git access" do
      GitHub.stubs(:anonymous_git_access_enabled?).returns(true)

      @simple.lock_anonymous_git_access(@simple.owner)
      assert @simple.config.enabled?(Configurable::AnonymousGitAccessLock::KEY)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @simple.set_visibility(actor: @simple.owner, visibility: "private") }
      @simple.reload
      refute @simple.config.enabled?(Configurable::AnonymousGitAccessLock::KEY)
    end

    test "disables tiered reporting" do
      @biz_grit.enable_tiered_reporting(actor: @biz_org_admin)
      assert_predicate @biz_grit, :tiered_reporting_explicitly_enabled?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_grit.set_visibility(actor: @biz_org_admin, visibility: "private") }
      @biz_grit.reload
      assert_predicate @biz_grit, :tiered_reporting_explicitly_disabled?
    end
  end

  context "Toggling the visibility of a private repo to public" do
    test "works if it is the only repo in the network" do
      assert_predicate @ambition, :private?
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @ambition.set_visibility(actor: @ambition.owner, visibility: "public") }
      assert_predicate @ambition.reload, :public?
    end

    test "unlocks the repo if it was billing locked" do
      @ambition.lock_for_billing
      assert_predicate @ambition, :locked_on_billing?
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @ambition.set_visibility(actor: @ambition.owner, visibility: "public") }
      refute_predicate @ambition.reload, :locked_on_billing?
      refute @ambition.locked
    end

    test "enables the owner if their private repo count falls below their plan limit" do
      (1..5).each { |n| create(:private_repository, name: "ambition#{n}", owner: @defunkt) }
      @defunkt.update(plan: "micro")
      @defunkt.reload

      @defunkt.enable_or_disable!
      assert @defunkt.disabled

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) {  @ambition.reload.set_visibility(actor: @ambition.owner, visibility: "public") }
      assert_predicate @defunkt.reload, :enabled?
    end

    test "extracts any forks into their own private networks if repo is root" do
      @ambition.add_member(@mojombo)
      @ambition.add_member(@pj)

      example_repo :defunkt_ambition, @ambition
      fork1 = create(:fork_repository, forker: @mojombo, fork_repo: @ambition, clone_fork: true)
      fork1.add_member(@maddox)
      fork2 = create(:fork_repository, forker: @pj, fork_repo: @ambition, clone_fork: true)
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @ambition.set_visibility(actor: @ambition.owner, visibility: "public") }
      assert_predicate @ambition.reload, :public?
      assert_predicate fork1.reload, :private?
      assert_predicate fork2.reload, :private?
      refute_equal @ambition.reload_network, fork1.reload_network
      refute_equal @ambition.network, fork2.network
      refute_equal fork1.network, fork2.network
      refute fork1.locked
      refute fork2.locked
    end

    test "extracts detached public fork into its own network if repo is root" do
      fork1 = create(:fork_repository, forker: @maddox, fork_repo: @grit)
      fork2 = create(:fork_repository, forker: @pj, fork_repo: @grit)
      fork1fork = create(:fork_repository, forker: @defunkt, fork_repo: fork1)

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @grit.set_visibility(actor: @grit.owner, visibility: "private") }

      assert_predicate @grit.reload, :private?
      assert_predicate fork1.reload, :public?
      assert_predicate fork2.reload, :public?
      assert_predicate fork1fork.reload, :public?

      refute_equal @grit.network, fork1.network
      assert_equal fork1.network, fork2.network
      assert_equal fork1.network, fork1fork.network

      refute @grit.locked
      refute fork1.locked
      refute fork2.locked
      refute fork1fork.locked
    end

    test "only extracts private forks into own networks if repo is root" do
      @fork1 = create(:fork_repository, forker: @maddox, fork_repo: @simple)
      @fork2 = create(:fork_repository, forker: @pj, fork_repo: @simple)

      # Change the visibility but don't extract it from the network
      VisibilityRepositoryOrchestration.any_instance.stubs(:detach_repo?).returns(false)
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) {  @simple.set_visibility(actor: @simple.owner, visibility: "private") }
      VisibilityRepositoryOrchestration.any_instance.unstub(:detach_repo?)
      @simple.reload
      assert_predicate @simple, :private?
      assert_predicate @fork1, :public?
      assert_predicate @fork2, :public?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) {  @simple.set_visibility(actor: @simple.owner, visibility: "public") }
      assert_predicate @simple.reload, :public?
      assert_predicate @fork1, :public?
      assert_predicate @fork2, :public?
      assert_equal @simple.network, @fork1.network
      assert_equal @simple.network, @fork2.network
    end

    test "triggers a 'repository.access' instrumentation event" do
      GitHub.context.push(actor_id: @ambition.owner.id)
      events = subscribe "repo.access"
      expected_payload = {
        user: @ambition.owner.login,
        user_id: @ambition.owner.id,
        repo: @ambition.name_with_owner,
        repo_id: @ambition.id,
        public_repo: !@ambition.public?,
        fork_source: @ambition.root.name_with_owner,
        fork_source_id: @ambition.root.id,
        access: :public,
        visibility: :public,
        previous_visibility: @ambition.visibility,
        actor_id: @ambition.owner.id,
        actor: @ambition.owner.login,
      }

      assert_predicate @ambition, :private?
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) {  @ambition.set_visibility(actor: @ambition.owner, visibility: "public") }
      assert_predicate @ambition.reload, :public?

      assert event = events.pop, "expected an event to be triggered"
      assert_equal expected_payload, event.payload
    end

    test "creates a PublicEvent for the timeline" do
      GitHub.reset_stratocaster

      assert_predicate @ambition, :private?
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob, ProcessEventJob]) do
        @ambition.set_visibility(actor: @ambition.owner, visibility: "public")
      end
      @ambition.reload
      assert_predicate @ambition, :public?

      assert event = GitHub.stratocaster_store.last.to_hash.deep_symbolize_keys
      assert_equal "PublicEvent", event[:event_type]
      assert_equal "ambition", event[:repo][:name]
    end

    test "enables network alternates" do
      example_repo :defunkt_ambition, @ambition
      assert_predicate @ambition, :private?
      refute_predicate @ambition, :shared_storage_enabled?
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @ambition.set_visibility(actor: @ambition.owner, visibility: "public") }
      assert_predicate @ambition.reload, :shared_storage_enabled?
    end

    test "locks private forks and forks of forks if the fork owners are at their plan limit" do
      @mojombo.update plan: "free"
      @pj.update plan: "free"
      @ambition.add_member(@mojombo)
      @ambition.add_member(@pj)
      @fork1 = create(:fork_repository, forker: @mojombo, fork_repo: @ambition, clone_fork: true)
      @fork1.add_member(@maddox)
      @fork2 = create(:fork_repository, forker: @pj, fork_repo: @ambition, clone_fork: true)

      @fork1fork = create(:fork_repository, forker: @maddox, fork_repo: @fork1, clone_fork: true)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @ambition.set_visibility(actor: @ambition.owner, visibility: "public") }

      refute_predicate @fork1.reload, :locked_on_billing?
      refute_predicate @fork2.reload, :locked_on_billing?
      refute_predicate @fork1fork.reload, :locked_on_billing?
    end

    test "fails to set public visibility if trade controls restricted org is owner" do
      org = create :organization
      repo = create :private_repository, owner: org
      org.trade_controls_restriction.full!
      assert_predicate org, :has_any_trade_restrictions?
      assert_predicate repo, :disabled?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: org.admin, visibility: "public") }

      refute_predicate repo.reload, :public?
      assert_match ::TradeControls::Notices.notice_as_plaintext(:organization_owned_repo_disabled), repo.errors[:visibility_restricted].first
    end

    test "succeeds to set public visibility if org is partially trade controls restricted" do
      org = create :organization
      repo = create :private_repository, owner: org
      org.trade_controls_restriction.partial!
      assert_predicate org, :has_partial_trade_restrictions?
      assert_predicate repo, :disabled?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: org.admin, visibility: "public") }
      assert_predicate repo.reload, :public?
    end

    test "succeeds to set public visibility if org is tier_1 trade controls restricted" do
      org = create :organization, plan: "free"
      repo = create :private_repository, owner: org
      org.trade_controls_restriction.tier_1!
      assert_predicate org, :has_tier_1_trade_restrictions?
      assert_predicate repo, :disabled?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: org.admin, visibility: "public") }
      assert_predicate repo.reload, :public?
    end
  end

  context "Setting the visibility of a public repo to internal" do
    test "makes members collaborators" do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @biz_simple.owner.stubs(:at_private_repo_limit?).returns(false)
        @biz_simple.set_visibility(actor: @biz_org_admin, visibility: "internal")
        assert_predicate @biz_simple.reload, :internal?
        assert @biz_simple.add_member(@pj)

        assert_difference "@biz_simple.owner.reload.collaborators_count", -1 do
          perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_simple.set_visibility(actor: @biz_org_admin, visibility: "public") }
        end
      end
    end

    test "succeeds if repository has trade restricted invitees" do
      invitation = create(:repository_invitation, repository: @biz_simple)
      invitee = invitation.invitee
      invitee.trade_controls_restriction.full!

      assert invitee.has_any_trade_restrictions?, "expected user to be trade restricted"
      assert_equal 1, @biz_simple.invitees.count

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_simple.set_visibility(actor: @biz_org_admin, visibility: "internal") }

      assert_predicate @biz_simple.reload, :internal?
    end

    test "succeeds if repository has trade restricted collaborators" do
      user = create(:user)
      @biz_simple.add_member(user)
      user.trade_controls_restriction.full!
      assert user.has_any_trade_restrictions?, "expected user to be trade restricted"

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_simple.set_visibility(actor: @biz_simple.owner, visibility: "internal") }

      assert_predicate @biz_simple.reload, :internal?
    end

    test "does not destroy pages", skip_enterprise: true do
      repo = create(:public_repository, owner: @biz_org)
      page = create(:page, repository: repo)

      assert repo.page
      refute repo.private?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: @biz_org_admin, visibility: "internal") }
      repo.reload

      assert repo.plan_supports?(:pages)
      assert repo.page
      assert_predicate repo, :internal?
    end

    test "does not destroy protected branch rules", skip_enterprise: true do
      repo = create(:public_repository, owner: @biz_org)
      protected_branch = create(:protected_branch, repository: repo)

      refute_empty repo.protected_branches
      refute_predicate repo, :private?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: @biz_org_admin, visibility: "internal") }
      repo.reload

      assert repo.plan_supports?(:protected_branches)
      refute_predicate repo.protected_branches, :empty?
      assert_predicate repo, :internal?
    end

    test "if root, detaches into a new network and elects a new root for network" do
      @biz_simple.owner.stubs(:at_private_repo_limit?).returns(false)
      @biz_fork = create(:fork_repository, forker: @biz_org_admin, fork_repo: @biz_simple)
      assert_predicate @biz_simple, :public?

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @biz_simple.set_visibility(actor: @biz_simple.owner, visibility: "internal") }
      assert_predicate @biz_simple.reload, :internal?
      assert_predicate @biz_fork.reload, :public?
      refute_equal @biz_simple, @biz_fork.network.root
      refute_equal @biz_simple.network, @biz_fork.network
      assert_nil @biz_simple.parent_id
    end

    test "triggers a 'repository.access' instrumentation event" do
      GitHub.context.push(actor_id: @biz_simple.owner.id)
      events = subscribe "repo.access"
      expected_payload = {
        org: @biz_simple.owner.login,
        org_id: @biz_simple.owner.id,
        repo: @biz_simple.name_with_owner,
        repo_id: @biz_simple.id,
        public_repo: !@biz_simple.public?,
        fork_source: @biz_simple.root.name_with_owner,
        fork_source_id: @biz_simple.root.id,
        access: :internal,
        visibility: :internal,
        previous_visibility: @biz_simple.visibility,
        actor_id: @biz_simple.owner.id,
        actor: @biz_simple.owner.login,
      }

      assert @biz_simple.public?
      @biz_simple.owner.stubs(:at_private_repo_limit?).returns(false)
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_simple.set_visibility(actor: @biz_simple.owner, visibility: "internal") }
      assert_predicate @biz_simple.reload, :internal?

      assert event = events.pop, "expected an event to be triggered"
      assert_equal expected_payload, event.payload
    end

    test "does not create a PublicEvent" do
      GitHub.reset_stratocaster

      assert_predicate @biz_simple, :public?
      @biz_simple.owner.stubs(:at_private_repo_limit?).returns(false)
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_simple.set_visibility(actor: @biz_simple.owner, visibility: "internal") }
      assert_predicate @biz_simple.reload, :internal?

      assert_nil GitHub.stratocaster_store.last
    end

    test "does not disable network alternates" do
      @biz_grit.enable_or_disable_shared_storage
      assert @biz_grit.shared_storage_enabled?
      @biz_grit.set_visibility(actor: @biz_grit.owner, visibility: "internal")
      assert @biz_grit.shared_storage_enabled?
    end

    test "disables anonymous git access" do
      GitHub.stubs(:anonymous_git_access_enabled?).returns(true)

      @biz_simple.enable_anonymous_git_access(@biz_simple.owner)
      assert @biz_simple.config.enabled?(Configurable::AnonymousGitAccess::KEY)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_simple.set_visibility(actor: @biz_simple.owner, visibility: "internal") }
      refute @biz_simple.reload.config.enabled?(Configurable::AnonymousGitAccess::KEY)
    end

    test "unlocks anonymous git access" do
      GitHub.stubs(:anonymous_git_access_enabled?).returns(true)

      @biz_simple.lock_anonymous_git_access(@biz_simple.owner)
      assert @biz_simple.config.enabled?(Configurable::AnonymousGitAccessLock::KEY)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_simple.set_visibility(actor: @biz_simple.owner, visibility: "internal") }
      refute @biz_simple.reload.config.enabled?(Configurable::AnonymousGitAccessLock::KEY)
    end
  end

  context "Setting the visibility of a private repo to internal" do
    test "works if it is the only repo in the network" do
      assert @biz_ambition.private?
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_ambition.set_visibility(actor: @biz_ambition.owner, visibility: "internal") }
      assert_predicate @biz_ambition.reload, :internal?
    end

    test "triggers a 'repository.access' instrumentation event" do
      GitHub.context.push(actor_id: @biz_ambition.owner.id)
      events = subscribe "repo.access"
      expected_payload = {
        org: @biz_org.login,
        org_id: @biz_org.id,
        repo: @biz_ambition.name_with_owner,
        repo_id: @biz_ambition.id,
        public_repo: @biz_ambition.public?,
        fork_source: @biz_ambition.root.name_with_owner,
        fork_source_id: @biz_ambition.root.id,
        access: :internal,
        visibility: :internal,
        previous_visibility: @biz_ambition.visibility,
        actor_id: @biz_ambition.owner.id,
        actor: @biz_ambition.owner.login,
      }

      assert_predicate @biz_ambition, :private?
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_ambition.set_visibility(actor: @biz_ambition.owner, visibility: "internal") }
      assert_predicate @biz_ambition.reload, :internal?

      assert event = events.pop, "expected an event to be triggered"
      assert_equal expected_payload, event.payload
    end
  end

  context "Setting the visibility of an internal repo to private" do
    test "works if it is the only repo in the network" do
      assert_predicate @biz_internal_ambition, :internal?
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_internal_ambition.set_visibility(actor: @biz_internal_ambition.owner, visibility: "private") }
      assert_predicate @biz_internal_ambition.reload, :private?
      refute_predicate @biz_internal_ambition, :internal?
    end

    test "triggers a 'repository.access' instrumentation event" do
      GitHub.context.push(actor_id: @biz_internal_ambition.owner.id)
      events = subscribe "repo.access"
      expected_payload = {
        org: @biz_org.login,
        org_id: @biz_org.id,
        repo: @biz_internal_ambition.name_with_owner,
        repo_id: @biz_internal_ambition.id,
        public_repo: @biz_internal_ambition.public?,
        fork_source: @biz_internal_ambition.root.name_with_owner,
        fork_source_id: @biz_internal_ambition.root.id,
        access: :private,
        visibility: :private,
        previous_visibility: @biz_internal_ambition.visibility,
        actor_id: @biz_internal_ambition.owner.id,
        actor: @biz_internal_ambition.owner.login,
      }

      assert_predicate @biz_internal_ambition, :internal?
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_internal_ambition.set_visibility(actor: @biz_internal_ambition.owner, visibility: "private") }
      assert_predicate @biz_internal_ambition.reload, :private?
      refute_predicate @biz_internal_ambition, :internal?

      assert event = events.pop, "expected an event to be triggered"
      assert_equal expected_payload, event.payload
    end
  end

  context "Setting the visibility of an internal repo to public" do
    test "works if it is the only repo in the network" do
      assert_predicate @biz_internal_ambition, :internal?
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_internal_ambition.set_visibility(actor: @biz_internal_ambition.owner, visibility: "public") }
      assert_predicate @biz_internal_ambition.reload, :public?
    end

    test "unlocks the repo if it was billing locked" do
      @biz_internal_ambition.lock_for_billing
      assert @biz_internal_ambition.locked_on_billing?
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @biz_internal_ambition.set_visibility(actor: @biz_internal_ambition.owner, visibility: "public") }
      refute @biz_internal_ambition.reload.locked_on_billing?
      refute @biz_internal_ambition.locked
    end

    test "extracts any forks into their own private networks if repo is root" do
      @biz_org.add_member(@mojombo)
      @biz_org.add_member(@pj)
      fork1 = create(:fork_repository, fork_repo: @biz_internal_ambition, forker: @mojombo, clone_fork: true)
      fork1.add_member(@maddox)
      fork2 = create(:fork_repository, forker: @pj, fork_repo: @biz_internal_ambition, clone_fork: true)

      # Temporarily change the visibility on the root Repo to allow the now unsupported 2-level internal fork creation
      @biz_internal_ambition.send(:set_permission, Repository::PRIVATE_VISIBILITY)
      fork1fork = create(:fork_repository, forker: @maddox, fork_repo: fork1, clone_fork: true)

      @biz_internal_ambition.send(:set_permission, Repository::INTERNAL_VISIBILITY)
      assert_equal @biz_internal_ambition.internal?, true

      assert_predicate @biz_internal_ambition, :internal?
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @biz_internal_ambition.set_visibility(actor: @biz_internal_ambition.owner, visibility: "public") }
      assert_predicate @biz_internal_ambition.reload, :public?
      assert_predicate fork1.reload, :private?
      assert_predicate fork2.reload, :private?
      refute_equal @biz_internal_ambition.reload_network, fork1.reload_network
      refute_equal @biz_internal_ambition.network, fork2.network
      refute_equal fork1.network, fork2.network
      refute_predicate fork1, :locked
      refute_predicate fork2, :locked

      assert_predicate fork1fork.reload, :private?
      assert_equal fork1.network, fork1fork.network
      refute_predicate fork1fork, :locked
    end

    test "only extracts private forks into own networks if repo is root" do
      fork1 = create(:fork_repository, forker: create(:user), fork_repo: @biz_simple)
      fork2 = create(:fork_repository, forker: create(:user), fork_repo: @biz_simple)

      # Change the visibility but don't extract it from the network
      VisibilityRepositoryOrchestration.any_instance.stubs(:detach_repo?).returns(false)
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_simple.set_visibility(actor: @biz_simple.owner, visibility: "internal") }
      VisibilityRepositoryOrchestration.any_instance.unstub(:detach_repo?)

      assert_predicate @biz_simple.reload, :internal?
      assert_predicate fork1, :public?
      assert_predicate fork2, :public?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_simple.set_visibility(actor: @biz_simple.owner, visibility: "public") }
      assert_predicate @biz_simple.reload, :public?
      assert_predicate fork1, :public?
      assert_predicate fork2, :public?
      assert_equal @biz_simple.network, fork1.network
      assert_equal @biz_simple.network, fork2.network
    end

    test "triggers a 'repository.access' instrumentation event" do
      GitHub.context.push(actor_id: @biz_internal_ambition.owner.id)
      events = subscribe "repo.access"
      expected_payload = {
        org: @biz_org.login,
        org_id: @biz_org.id,
        repo: @biz_internal_ambition.name_with_owner,
        repo_id: @biz_internal_ambition.id,
        public_repo: !@biz_internal_ambition.public?,
        fork_source: @biz_internal_ambition.root.name_with_owner,
        fork_source_id: @biz_internal_ambition.root.id,
        access: :public,
        visibility: :public,
        previous_visibility: @biz_internal_ambition.visibility,
        actor_id: @biz_internal_ambition.owner.id,
        actor: @biz_internal_ambition.owner.login,
      }

      assert_predicate @biz_internal_ambition, :internal?
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @biz_internal_ambition.set_visibility(actor: @biz_internal_ambition.owner, visibility: "public") }
      assert_predicate @biz_internal_ambition.reload, :public?

      assert event = events.pop, "expected an event to be triggered"
      assert_equal expected_payload, event.payload
    end

    test "creates a PublicEvent for the timeline" do
      GitHub.reset_stratocaster

      assert_predicate @biz_internal_ambition, :internal?
      perform_enqueued_jobs(only: [ProcessEventJob, RepositoryOrchestrationJob]) do
        @biz_internal_ambition.set_visibility(actor: @biz_internal_ambition.owner, visibility: "public")
      end
      assert @biz_internal_ambition.reload.public?

      assert event = GitHub.stratocaster_store.last.to_hash.deep_symbolize_keys
      assert_equal "PublicEvent", event[:event_type]
      assert_equal "biz-internal-ambition", event[:repo][:name]
    end

    test "enables network alternates" do
      example_repo :defunkt_ambition, @biz_internal_ambition
      assert @biz_internal_ambition.private?

      assert !@biz_internal_ambition.shared_storage_enabled?
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @biz_internal_ambition.set_visibility(actor: @biz_internal_ambition.owner, visibility: "public") }
      assert @biz_internal_ambition.reload.shared_storage_enabled?
    end
  end

  context "interaction with can_change_repo_visibility? check" do
    test "visibility changes when user is an admin of the owning organization" do
      org = create(:organization, plan: "business")
      owner = org.admins.first
      org.block_members_from_changing_repo_visibility(actor: owner)
      repo = create(:private_repository, owner: org)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: owner, visibility: "public") }

      assert repo.reload.public?, "repo should have changed visibility for org owner"
    end

    test "visibility changes when user is a member and the organization allows changing repo visibility" do
      org = create(:organization, plan: "business")
      member = create(:user)
      org.add_member(member)
      org.allow_members_to_change_repo_visibility(actor: org.admins.first)
      repo = create(:private_repository, owner: org)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: member, visibility: "public") }

      assert repo.reload.public?, "repo visibility should have changed for org owner"
    end

    test "does not change to public when the user is a member and the org has disabled changing repo visibility" do
      org = create(:organization, plan: "business")
      org.block_members_from_changing_repo_visibility(actor: org.admins.first)
      member = create(:user)
      org.add_member(member)
      repo = create(:private_repository, owner: org)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: member, visibility: "public") }

      refute repo.reload.public?, "repo should still be private"
      assert_match /can't be changed by this user/, repo.errors[:visibility].first
    end

    test "changes to private when user is an admin of an org with lic_r commercial restriction" do
      org = create(:organization, plan: "business")
      enable_feature_flag(:live_sdn_screening, org)

      create(:account_screening_profile, :lic_r_enabled_and_restricted, owner: org)
      org.reload
      repo = create(:public_repository, owner: org)

      assert_predicate org.trade_screening_record, :lic_r?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: org.admins.first, visibility: "private") }

      assert repo.reload.private?, "repo should have changed visibility for org owner"
    end

    test "does not change to private when user is an admin of an org with true_match commercial restriction", skip_unless: :billing_enabled? do
      org = create(:organization, plan: "business")
      enable_feature_flag(:live_sdn_screening, org)

      create(:account_screening_profile, :lic_r_enabled_and_restricted, owner: org)
      repo = create(:public_repository, owner: org)
      org.sdn_suspend(staff_user: User.staff_user, reason: "test")

      assert_predicate org.trade_screening_record, :true_match?

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: org.admins.first, visibility: "private") }

      refute repo.reload.private?, "repo should still be public"
      assert_match /can't be private. We are unable to provide this feature/, repo.errors[:visibility].first
    end

    test "does not change to private when the user is a member and the org has disabled changing repo visibility" do
      org = create(:organization, plan: "business")
      org.block_members_from_changing_repo_visibility(actor: org.admins.first)
      member = create(:user)
      org.add_member(member)
      repo = create(:public_repository, owner: org)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: member, visibility: "private") }

      refute repo.reload.private?, "repo should still be public"
      assert_match /can't be changed by this user/, repo.errors[:visibility].first
    end

    test "does not change when the user is not a member of the organization" do
      org = create(:organization, plan: "business")
      org.block_members_from_changing_repo_visibility(actor: org.admins.first)
      non_member = create(:user)
      repo = create(:private_repository, owner: org)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: non_member, visibility: "public") }

      refute repo.reload.public?, "repo should still be private"
      assert_match /can't be changed by this user/, repo.errors[:visibility].first
    end
  end
end
