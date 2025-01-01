# typed: true
# frozen_string_literal: true

require "test_helper"

class UserTransformingIntoAnOrganizationTest < GitHub::IntegrationTestCase
  include DogstatsTestHelpers
  skip_with_all_emus

  fixtures do
    @to_transform = create :user
    @owned_repo = create :repository, owner: @to_transform
    @owned_repo_issue = create :issue, repository: @owned_repo

    @owner = create(:user)

    @user = create :staff_admin_user, plan: "medium"
    create(:user_session, user: @user)
    @user.profile_hireable = true
    @user.profile_bio = "Ruby hacker."
    @user.profile_name = "The Dude"
    create(:public_key, user: @user)
    @user.save

    3.times do
      @user.add_email(Faker::Internet.email)
    end
    assert_equal 4, @user.emails.size

    @user_email = @user.email
    @user_billing_email = @user.billing_email
    @user_gravatar_email = @user.gravatar_email
    @old_password = @user.password_hash

    @user2 = create(:user)
    @user3 = create(:user)
    @user4 = create(:user)
    @user5 = create(:user)

    @user.follow(@user2)
    @user.follow(@user4)
    @user3.follow(@user)

    blocked_user = create(:user)
    @user.block(blocked_user)
    blocking_user = create(:user)
    blocking_user.block(@user)

    @repo = create(:private_repository, owner: @user)
    @repo2 = create(:repository, owner: @user)
    @user.unwatch_repo(@repo2)
    @repo3 = create(:private_repository, owner: @user)
    @repo4 = create(:private_repository, owner: @user)
    @repo5 = create(:public_repository, owner: @user)

    # collaborating repos and organizations
    @collab_org = create(:organization)
    @team = create :team, organization: @collab_org
    @team.add_member @user
    @collab_repo = create(:repository)
    @collab_repo.add_member @user, @collab_repo.owner, false
    @invite_org = create(:organization)
    @invite_org.invite(@user, inviter: @invite_org.admin)

    @invite_repo_owner = create(:user)
    @invite_repo = create(:repository, owner: @invite_repo_owner)
    RepositoryInvitation.invite_to_repo(@user, @invite_repo_owner, @invite_repo)

    @unowned_repo = create(:repository)
    @user.watch_repo(@unowned_repo)

    @repo.add_member(@user2, @user, false)
    @repo.add_member(@user3, @user, false)
    @repo3.add_member(@user2, @user, false)
    @repo3.add_member(@user3, @user, false)
    @repo4.add_member(@user4, @user, false)

    @forked_private = create(:fork_repository, forker: @user2, fork_repo: @repo)
    @forked_public = create(:fork_repository, forker: @user2, fork_repo: @repo5)
    @forked_by_nonmember_public = create(:fork_repository, forker: @user5, fork_repo: @repo5)

    base_ref = @collab_repo.heads.find_or_build("master")
    base_ref.append_commit({ message:  "a change", committer:  @collab_repo.owner }, @collab_repo.owner) do |files|
      files.add("file001", "foo")
    end

    head_ref = @collab_repo.heads.create("feature-branch", base_ref.target, @collab_repo.owner)
    head_ref.append_commit({ message:  "another change", committer:  @repo.owner }, @repo.owner) do |files|
      files.add("file002", "foo")
    end

    @issue = create(:issue, user:  @collab_repo.owner, repository:  @collab_repo)
    create(:issue, user:  @collab_repo.owner, repository:  @collab_repo)
    create(:issue, user:  @collab_repo.owner, repository:  @collab_repo)
    @pull  = create(:pull_request,
      repository:  @collab_repo,
      base_repository:  @collab_repo,
      base_user:  @collab_repo.owner,
      base_ref:  "master",
      head_repository:  @collab_repo,
      head_user:  @collab_repo.owner,
      head_ref:  "feature-branch",
      issue:  @issue,
    )

    @review_request = @pull.review_requests.create(reviewer: @user)

    @user2.watch_repo(@repo)
    assert @user2.watching_repo?(@repo)

    @user.star(@repo)
    assert @repo.starred_by?(@user)
    gist = create :gist
    @user.star(gist)
    assert gist.starred_by?(@user)

    InteractionSetting.create!(user: @user, show_blocked_contributors_warning: true)
    assert @user.show_blocked_contributors_warning?

    if GitHub.single_business_environment?
      @business = create(:global_business)
    else
      @business = create(:business)
    end

    @business_org = create(:organization)
    @business.add_organization(@business_org)
    @business_owner = create(:user)
    @business.add_owner(@business_owner, actor: nil)
    @billing_manager = create(:user)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    GitHub.flipper[:default_issue_types_job_killswitch].disable
  end

  context "::transform!" do
    test "becomes an Organization" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })
      assert org.organization?
    end

    test "instruments transform" do
      events = subscribe "org.transform"
      user   = create(:user)
      owner  = create(:user)
      org    = Organization.transform!(user, owner, plan: "business_plus")

      expected_payload = {
        org: org.login,
        org_id: org.id,
        owner: owner.login,
        tos_sha: TosAcceptance.current_sha,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "does not instrument transform if it fails" do
      events = subscribe "org.transform"
      user   = create :user, login: "transform-should-fail"
      owner  = create :user

      user.stubs(:save!).raises(ActiveRecord::RecordInvalid)
      assert_raises ActiveRecord::RecordInvalid do
        org = Organization.transform!(user, owner, plan: "business_plus")
      end

      assert_empty events
    end

    test "clears all newsies data when called" do
      Notifications::Subscriptions.expects(:async_delete_user_subscriptions).with(@to_transform.id)
      Organization.transform!(@to_transform, @owner)
    end

    test "creates user_labels for the org" do
      Organization.transform!(@to_transform, @owner)
      org = Organization.find(@to_transform.id)
      assert_equal UserLabel.initial_labels.count, org.user_labels.count
    end

    test "clears all issue assignments" do
      @owned_repo_issue.add_assignees(@to_transform)
      refute_empty @owned_repo_issue.reload.assignees

      Organization.transform!(@to_transform, @owner)
      assert_empty @owned_repo_issue.reload.assignees
    end

    test "clears account screening profile" do
      create(:account_screening_profile, owner: @to_transform)
      org = Organization.transform!(@to_transform, @owner)

      assert_predicate @to_transform.trade_screening_record, :destroyed?
    end

    test "fails to clear account screening profile that's in restrictive state" do
      create(:account_screening_profile, :hit_in_review, owner: @to_transform)

      assert_raises AccountScreeningProfile::AccountScreeningProfileDeleteError, "Current SDN status does not allow personal profile deletion" do
        Organization.transform!(@to_transform, @owner)
      end

      refute_predicate @to_transform.trade_screening_record, :destroyed?
    end

    test "ensures orgs are no longer participants" do
      issue = create(:issue, repository: @owned_repo, user: @to_transform)

      Organization.transform!(@to_transform, @owner)
      assert_empty issue.reload.participants
    end

    test "ensures transformed account is no longer an enterprise owner" do
      @business.add_owner(@to_transform, actor: @business.owners.first)
      assert_includes @business.owners, @to_transform

      Organization.transform!(@to_transform, @owner)

      org = Organization.find(@to_transform.id)
      refute_includes @business.owners, org
    end

    test "invokes method to terminate account successor agreements" do
      SuccessorInvitation.expects(:terminate_all).once.with(@to_transform)

      Organization.transform!(@to_transform, @owner)
    end

    test "it enqueues trade controls compliance checks for org admins" do
      user = create(:user)
      owner  = create(:user)

      assert_enqueued_with job: TradeControls::OrganizationComplianceCheckJob, args: [user.id, reason: :organization_admin] do
        Organization.transform!(user, owner, plan: "business_plus")
      end
    end unless GitHub.enterprise?

    test "dismisses review requests" do
      Organization.transform!(@user, @owner, { plan: "silver" })
      assert @review_request.reload.dismissed?, "Review requests should be dismissed when a user transforms."
    end

    test "destroys review_requested and review_request_removed issue events" do
      review_requested_event = IssueEvent.where(
        event: "review_requested",
        actor_id: @pull.user.id,
        issue_id: @pull.issue.id
      ).first
      review_requested_event_detail = IssueEventDetail.where(
        issue_event_id: review_requested_event.id
      ).first
      refute_nil review_requested_event
      refute_nil review_requested_event_detail

      @review_request.dismiss
      @review_request.save

      review_request_removed_event = IssueEvent.where(
        event: "review_request_removed",
        actor_id: @pull.user.id,
        issue_id: @pull.issue.id
      ).first
      review_request_removed_event_detail = IssueEventDetail.where(
        issue_event_id: review_request_removed_event.id
      ).last
      refute_nil review_request_removed_event
      refute_nil review_requested_event_detail

      Organization.transform!(@user, @owner, { plan: "silver" })

      assert_empty IssueEvent.where(
        event: %w(review_requested review_request_removed),
        actor_id: @pull.user.id,
        issue_id: @pull.issue.id
      )
      assert_empty IssueEventDetail.where(
        subject_id: @user,
        subject_type: "User",
        review_request_id: @review_request.id
      )
    end

    test "removes repository and gist stars" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })

      assert_equal 0, org.starred_repositories_count
      assert_equal 0, org.starred_gists.count
    end

    test "removes interaction warning setting" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })

      refute org.show_blocked_contributors_warning?
      assert_nil org.interaction_setting
    end

    test "retains repositories" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })

      assert_equal 5, org.repositories.size
      assert org.repositories.all? { |r| r.organization == org }
    end

    test "enqueues rebuild of contributions" do
      new_owner = create :user
      user = create :user
      repository = create(:public_repository, :minimal, owner: user)
      create :issue, repository: repository, user: user

      assert_enqueued_with(
        job: UserContributionsBackfillJob,
        args: [[repository.id], user.id]
      ) do
        Organization.transform!(user, new_owner, { plan: "silver" })
      end
    end

    test "retains user memexes as org memexes" do
      user_to_transform = create(:user, login: "user-to-transform")
      memex_project = create(:memex_project, owner: user_to_transform)
      new_owner = create(:user, login: "new-org-owner")
      org = Organization.transform!(user_to_transform, new_owner)

      memex_project.reload
      assert_equal 1, org.memex_projects.count
      assert_equal memex_project, org.memex_projects.first
      assert_equal org, memex_project.owner
      assert_equal "Organization", memex_project.owner_type
      assert memex_project.viewer_is_admin?(new_owner)
    end

    test "retains user projects as org projects" do
      user = create(:user)
      project = create(:project, owner: user)
      org = Organization.transform!(user, @owner)

      project.reload

      assert_equal org, project.owner
      assert_equal 1, org.projects.count
      assert_equal project, org.projects.first
      assert_equal "Organization", project.owner_type
    end

    test "removes all emails" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal 0, org.emails.size
    end

    test "removes all email roles" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal 0, org.email_roles.count
    end

    test "associates private forks with the org" do
      Organization.transform!(@user, @owner, { plan: "silver" })
      assert @forked_private.reload.in_organization?
    end

    test "doesn't touch public forks" do
      Organization.transform!(@user, @owner, { plan: "silver" })
      assert !@forked_public.in_organization?
      assert !@forked_by_nonmember_public.in_organization?
    end

    test "erases SSH keys" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal [], org.public_keys
    end

    test "previously used email addresses are available for signup" do
      Organization.transform!(@user, @owner, { plan: "silver" })
      assert_nil UserEmail.find_by(email: @user_email)
    end

    test "sets billing email" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal @user_billing_email, org.billing_email
    end

    test "sets gravatar email" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal @user_gravatar_email, org.gravatar_email
    end

    test "changes password" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })
      refute_equal @old_password, org.password_hash
    end

    test "sets gh_role to nil" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })
      assert_nil org.gh_role
    end

    test "erases job profile" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })
      assert_nil org.profile_bio
      refute org.profile_hireable
    end

    test "sets staff badge preference to false" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })
      refute org.profile.display_staff_badge
    end

    test "maintains normal profile" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal "The Dude", org.profile_name
    end

    test "unfollows everyone" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal [], org.reload.following.reload
      assert_equal 0, org.following_count!
    end

    test "updates following counts of users who used to follow the transformed user" do
      Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal 0, @user3.following_count(viewer: nil)
    end

    test "updates follower counts of users who the org used to follow" do
      Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal 0, @user2.followers_count(viewer: nil)
      assert_equal 0, @user4.followers_count(viewer: nil)
    end

    test "removes all followers" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal [], org.followers
      assert_equal 0, org.followers_count!
    end

    test "removes all newsies subscriptions for the organization" do
      org = perform_enqueued_jobs only: Newsies::DeleteAllForUserJob do
        Organization.transform!(@user, @owner, { plan: "silver" })
      end
      assert_empty GitHub.newsies.subscriptions(org)
    end

    test "removes all of the transformed user's issue assignments" do
      user  = create(:user)
      issue = create(:issue)
      issue.repository.add_member(user)
      issue.add_assignees(user)
      issue.save

      assert_same_elements [user], issue.assignees

      assert_difference "Assignment.count", -1 do
        Organization.transform!(user, create(:user), { plan: "silver" })
      end

      assert_empty issue.reload.assignees
    end

    test "must have an owner" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal @owner, org.admins.first
    end

    test "enqueues only one OrganizationMailer#admin_added job" do
      OrganizationMailer.expects(:admin_added).returns(stub(deliver_later: nil))

      user = create(:user)
      owner = create(:user)
      Organization.transform!(user, owner, { plan: "silver" })
    end

    test "creates default issue types" do
      GitHub.flipper[:default_issue_types_job_killswitch].disable
      org = perform_enqueued_jobs only: SetupIssueTypesForOrganizationJob do
        Organization.transform!(@user, @owner, { plan: "silver" })
      end
      assert_equal 3, org.reload.issue_types.count
    end

    test "does not create default issue types if default_issue_types_job_killswitch FF enabled" do
      GitHub.flipper[:default_issue_types_job_killswitch].enable
      org = perform_enqueued_jobs only: SetupIssueTypesForOrganizationJob do
        Organization.transform!(@user, @owner, { plan: "silver" })
      end
      assert_equal 0, org.reload.issue_types.count
    end

    test "members still watch repositories" do
      Organization.transform!(@user, @owner, { plan: "silver" })
      assert @user2.watching_repo?(@repo)
    end

    test "fails if user has no primary email" do
      user = create(:user, created_at: 3.days.ago)
      user.email_roles.delete_all # remove primary email role
      user = User.find(user.id)   # force the user to get really reloaded
      assert_nil user.email
      assert !user.valid?, "user should be invalid since they have no primary emails"

      err = assert_raises Organization::TransformationFailed do
        Organization.transform(user, @owner, { plan: "silver" })
      end
      assert_equal("Transform requires a primary email on the user account.", err.message)
    end

    test "fails if user is restricted" do
      user = create(:user, created_at: 3.days.ago)
      personal_profile = create(:account_screening_profile, :hit_in_review, owner: user)
      assert_predicate user.trade_screening_record, :hit_in_review?

      err = assert_raises Organization::TransformationFailed do
        Organization.transform(user, @owner, { plan: "silver" })
      end
      assert_equal("Transform requires an unrestricted account.", err.message)
    end

    test "fails if user is the only owner of another organization" do
      user = create(:user)
      organization = create :organization, admin: user

      err = assert_raises Organization::TransformationFailed do
        Organization.transform(user, @owner, { plan: "silver" })
      end
      assert_equal("Cannot transform user because user is the last owner of #{organization}", err.message)
    end

    test "fails if user is the only owner of a business" do
      business_owner = create(:user)
      @business.add_owner(business_owner, actor: nil)
      @business.owners.each { |owner| @business.remove_owner(owner, actor: nil) unless owner == business_owner }
      err = assert_raises Organization::TransformationFailed do
        Organization.transform(business_owner, @owner, { plan: "silver" })
      end
      assert_equal("Cannot transform user because user is the last owner of Enterprise account #{@business}.", err.message)
    end

    test "creates a Transaction", skip_enterprise: true do
      org = Organization.transform!(@user, @owner, { plan: "silver" })

      transaction = org.transactions.last
      assert_equal "upgraded", transaction.action
      assert_equal "medium", transaction.old_plan.name
      assert_equal "silver", transaction.current_plan.name
    end

    test "does not create a Transaction for a free to free conversion" do
      user = create(:user, plan: "free")
      assert_no_difference "Transaction.count" do
        Organization.transform!(user, @owner)
      end
    end

    test "fails without an owner given" do
      user = create(:user)
      err = assert_raises Organization::TransformationFailed do
        Organization.transform(user, nil, { plan: "silver" })
      end
      assert_equal("Transform requires an owner.", err.message)
    end

    test "fails with more than one owner given" do
      user = create(:user)
      err = assert_raises Organization::TransformationFailed do
        Organization.transform(user, [@owner, create(:user)], { plan: "silver" })
      end
      assert_equal("Transform requires the owner be a user.", err.message)
    end

    test "fails with the org as an owner" do
      user = create(:user)
      err = assert_raises Organization::TransformationFailed do
        Organization.transform(user, user, { plan: "silver" })
      end
      assert_equal("This user will become an organization and can't be an owner.", err.message)
    end

    test "fails with a string owner given" do
      user = create(:user)
      err = assert_raises Organization::TransformationFailed do
        Organization.transform(user, "defunkt", { plan: "silver" })
      end
      assert_equal("Transform requires the owner be a user.", err.message)
    end

    test "fails with a bot user given" do
      bot = create(:integration).bot
      err = assert_raises Organization::TransformationFailed do
        Organization.transform(bot, @owner, { plan: "silver" })
      end
      assert_equal("Transform requires a primary email on the user account.", err.message)
    end

    test "fails with a bot owner given" do
      bot = create(:integration).bot
      user = create(:user)
      err = assert_raises Organization::TransformationFailed do
        Organization.transform(user, bot, { plan: "silver" })
      end
      assert_equal("Transform requires the owner be a user.", err.message)
    end

    test "succeeds with a company name" do
      user = create(:user)
      Organization.transform!(user, @owner, { plan: "business_plus", company_name: "dog" })

      assert_equal "dog", user.company_name
    end

    test "removes new org from any teams it was a member of" do
      Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal [], @team.members
    end

    test "removes new org from any repositories it was collaborating on" do
      Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal [], @collab_repo.members
    end

    test "removes invitations from any organizations it was invited to" do
      Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal [], @invite_org.pending_invitations
    end

    test "removes invitations from any repositories it was invited to" do
      Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal [], @user.received_repository_invitations
    end

    test "removes business owner invitations associated with user" do
      transforming_business_owner = create(:user)
      create :business_administrator_invitation, role: :owner, business: @business, inviter: @business_owner, invitee: transforming_business_owner
      assert @business.pending_admin_invitation_for(transforming_business_owner)
      perform_enqueued_jobs only: TransformUserIntoOrgJob do
        Organization.transform(transforming_business_owner, @owner)
      end
      assert_nil @business.pending_admin_invitation_for(transforming_business_owner)
    end

    test "removes business owner invitations associated with user email address" do
      transforming_business_owner = create(:user)
      create :business_administrator_invitation, :email, role: :owner, business: @business, inviter: @business_owner, email: transforming_business_owner.email
      assert @business.pending_admin_invitation_for(email: transforming_business_owner.email)
      perform_enqueued_jobs only: TransformUserIntoOrgJob do
        Organization.transform(transforming_business_owner, @owner)
      end
      assert_nil @business.pending_admin_invitation_for(email: transforming_business_owner.email)
    end

    test "removes billing manager invitations associated with user" do
      create :business_administrator_invitation, role: :billing_manager, business: @business, inviter: @business_owner, invitee: @billing_manager
      assert @business.pending_admin_invitation_for(@billing_manager)
      perform_enqueued_jobs only: TransformUserIntoOrgJob do
        Organization.transform(@billing_manager, @owner)
      end
      assert_nil @business.pending_admin_invitation_for(@billing_manager)
    end

    test "removes billing manager invitations associated with user email address" do
      create :business_administrator_invitation, :email, role: :billing_manager, business: @business, inviter: @business_owner, email: @billing_manager.email
      assert @business.pending_admin_invitation_for(email: @billing_manager.email)
      perform_enqueued_jobs only: TransformUserIntoOrgJob do
        Organization.transform(@billing_manager, @owner)
      end
      assert_nil @business.pending_admin_invitation_for(email: @billing_manager.email)
    end

    test "removes owner role from any businesses it was an owner of" do
      @business.owners.each { |owner| @business.remove_owner(owner, actor: nil) unless owner == @business_owner }
      @business.add_owner(@user2, actor: nil)
      @business.add_owner(@user3, actor: nil)

      assert_same_elements [@business_owner, @user2, @user3], @business.owners
      perform_enqueued_jobs only: TransformUserIntoOrgJob do
        Organization.transform(@business_owner, @owner)
      end
      assert_same_elements [@user2, @user3], @business.owners
      assert_nil BusinessUserAccount.find_by(user: @business_owner, business: @business)
    end

    test "removes billing manager role from any businesses it was billing manager of" do
      @business.billing.add_manager(@billing_manager, actor: @business_owner)
      assert @business.billing_manager?(@billing_manager)
      perform_enqueued_jobs only: TransformUserIntoOrgJob do
        Organization.transform(@billing_manager, @owner)
      end
      refute @business.billing_manager?(@billing_manager)
      assert_nil BusinessUserAccount.find_by(user: @billing_manager, business: @business)
    end

    unless GitHub.single_business_environment?
      test "removes BusinessUserAccount when user is transformed" do
        business_member = create(:user)
        @business_org.add_member(business_member)
        assert BusinessUserAccount.find_by(user: business_member, business: @business)
        perform_enqueued_jobs only: [TransformUserIntoOrgJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob] do
          Organization.transform(business_member, @owner)
        end
        assert_nil BusinessUserAccount.find_by(user: business_member, business: @business)
      end
    end

    test "removes user from all organizations" do
      org_member = create(:user)
      organization1 = create(:organization)
      organization2 = create(:organization)
      organization1.add_member(org_member)
      organization2.add_member(org_member)
      assert organization1.member?(org_member)
      assert organization2.member?(org_member)
      perform_enqueued_jobs only: [TransformUserIntoOrgJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob] do
        Organization.transform(org_member, @owner)
      end
      refute organization1.member?(org_member)
      refute organization2.member?(org_member)
    end

    test "removes dashboard notices" do
      user = create(:user)
      user.activate_notice :orgs_newbie
      assert_includes user.notices_for_dashboard, "orgs_newbie"

      Organization.transform!(user, @owner)
      refute_includes user.notices_for_dashboard, "orgs_newbie"
    end

    test "removes blocks to the user" do
      Organization.transform!(@user, @owner, { plan: "silver" })
      assert_equal 1, @user.ignored_users.count
      assert_empty @user.ignored_by_users
    end

    test "disables the Organization if over plan limit" do
      skip if GitHub.enterprise?

      user = create :user, plan: "medium"
      15.times { create(:private_repository, :minimal, owner: user) }
      Organization.transform!(user, @owner, { plan: "bronze" })

      assert user.reload.disabled?
    end

    test "revokes all access tokens" do
      user = create(:user)
      app  = create :oauth_application
      make_oauth user, [], app
      make_oauth user, []

      assert_equal 2, user.oauth_accesses.count
      Organization.transform!(user, @owner, { plan: "free" })

      assert_equal 0, user.oauth_accesses.reload.count
    end

    test "uninstalls user's integrations" do
      make_integration_installation(target: @to_transform)
      installs = @to_transform.integration_installations
      assert_changes -> { installs.count }, from: installs.count, to: 0 do
        Organization.transform!(@to_transform, @owner)
      end
    end

    if GitHub.oauth_application_policies_enabled?
      test "enables third-party application restrictions" do
        org = Organization.transform!(@user, @owner, { plan: "silver" })
        assert_predicate org, :restricts_oauth_applications?
      end
    else
      test "does not enable third-party application restrictions" do
        org = Organization.transform!(@user, @owner, { plan: "silver" })
        refute_predicate org, :restricts_oauth_applications?
      end
    end

    test "sets open member privilege defaults" do
      user = create(:user, login: "blah")
      org  = Organization.transform!(user, @owner, { plan: "silver" })

      assert org.members_can_create_repositories?
      assert_equal :read, org.default_repository_permission
    end

    test "grants admin to the new owner(s)" do
      org = Organization.transform!(@user, @owner, { plan: "silver" })
      assert_able @owner, :admin, org
    end

    test "grants admin permissions to org owners on dependent repos" do
      Organization.transform!(@user, @owner, { plan: "silver" })
      assert_able @owner, :admin, @repo
    end

    test "creates no teams" do
      user_to_transform = create(:user, login: "user-to-transform")
      collaborator = create(:user, login: "collaborator")
      new_owner = create(:user, login: "new-org-owner")

      repo = create(:repository, :minimal, owner: user_to_transform)
      repo.add_member(collaborator, user_to_transform)

      org = Organization.transform!(user_to_transform, new_owner)

      assert_empty org.teams
    end

    test "makes repository collaborators into outside collaborators" do
      user_to_transform = create(:user, login: "user-to-transform")
      collaborator = create(:user, login: "collaborator")
      new_owner = create(:user, login: "new-org-owner")

      repo = create(:repository, owner: user_to_transform)
      repo.add_member(collaborator, user_to_transform)

      org = Organization.transform!(user_to_transform, new_owner)
      perform_enqueued_jobs only: OrganizationCollaboratorBackfillJob

      assert_same_elements [repo], org.repositories
      assert_same_elements [collaborator], org.outside_collaborators
      assert_same_elements [collaborator], org.repositories.first.members
    end

    test "makes team collaborators of org-owned, user-forked repositories into outside collaborators" do
      user_to_transform = create(:user, login: "user-to-transform")
      new_owner = create(:user, login: "new-org-owner")
      collaborator = create(:user, login: "collaborator")

      existing_org = create(:organization, login: "existing-org")
      team = create :team, organization: existing_org
      team.add_member(collaborator)
      team.add_member(user_to_transform)

      repo = create(:repository, owner: existing_org)
      team.add_repository(repo, :push)

      forked_repo = create(:fork_repository, forker: user_to_transform, fork_repo: repo)
      team.add_repository(forked_repo, :push, allow_different_owner: true)

      org = Organization.transform!(user_to_transform, new_owner)

      assert_same_elements [forked_repo], org.repositories
      assert_same_elements [collaborator], org.outside_collaborators
      assert_same_elements [collaborator], org.repositories.first.members
    end

    test "doesn't send an invitation to the new owner" do
      user_to_transform = create(:user, login: "user-to-transform")
      new_owner         = create(:user, login: "new-owner")
      repo              = create(:repository, :minimal, owner: user_to_transform)
      repo.add_member(new_owner)

      assert_no_difference "OrganizationInvitation.count" do
        Organization.transform!(user_to_transform, new_owner, { plan: "silver" })
      end
    end

    test "does not update org-owned forks to point at the transformed org" do
      parent_user = create(:paid_user)
      new_owner = create(:user)
      repo = create(:private_repository, owner: parent_user)
      forking_org = create(:organization)
      owner = forking_org.admins.first
      assert repo.add_member(owner)
      org_fork = create(:fork_repository, forker: owner, organization: forking_org, fork_repo: repo)

      Organization.transform!(parent_user, new_owner, { plan: "silver" })

      assert_equal forking_org.id, org_fork.reload.organization_id
    end

    test "works correctly when a collaborator is chosen as the new owner" do
      transforming_org = create(:user, login: "transforming-org")
      new_owner = create(:user, login: "new-owner")
      repo = create(:repository, :minimal, owner: transforming_org)
      repo.add_member(new_owner)

      Organization.transform!(transforming_org, new_owner)
      transforming_org = Organization.find_by_login("transforming-org")

      assert transforming_org.organization?
      assert_same_elements [new_owner], transforming_org.admins
    end

    if GitHub.single_business_environment?
      test "adds created Organization to GitHub.global_business" do
        login = "really-want-to-be-an-org"
        user = create :user, login: login

        only = [TransformUserIntoOrgJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]
        perform_enqueued_jobs only: only do
          Organization.transform(user, @owner)
        end

        assert org = Organization.find_by(login: login)
        assert_includes GitHub.global_business.organizations, org
      end
    end

    test "disables private profile setting" do
      user = create(:user, :private_profile)
      assert_predicate user, :private_profile?

      assert org = Organization.transform!(user, @owner)
      refute_predicate org, :private_profile?
    end

    test "user_session AR lifecycle hooks are called on cleanup" do
      assert @user.sessions.active.any?

      perform_enqueued_jobs only: TransformUserIntoOrgJob do
        Organization.transform!(@user, @owner, plan: "silver")
      end

      refute @user.reload.sessions.active.any?
      assert_dogstats_increment 1, "user_session.destroy"
    end
  end

  context ".start_transform" do
    test "marks the user for transformation" do
      user = create(:user)
      assert Organization.start_transform(user)
      assert Organization.transforming?(user)
    end

    test "returns false when the user is already being transformed" do
      user = create(:user)
      Organization.start_transform(user)
      refute Organization.start_transform(user)
    end

    test "returns false when KV is unavailable" do
      GitHub.kv.stubs(:setnx).raises(GitHub::KV::UnavailableError) # rubocop:todo GitHub/DoNotUseGlobalKv
      user = create(:user)
      refute Organization.start_transform(user)
    end
  end

  context ".end_transform" do
    test "unmarks an org as being transformed" do
      user = create(:user)
      Organization.start_transform(user)
      assert Organization.transforming?(user)
      Organization.end_transform(user)
      refute Organization.transforming?(user)
    end

    test "ignores KV failures" do
      user = create(:user)
      Organization.start_transform user
      GitHub.kv.stubs(:del).raises(GitHub::KV::UnavailableError) # rubocop:todo GitHub/DoNotUseGlobalKv
      Organization.end_transform user
      assert Organization.transforming?(user), "should leave the flag untouched"
    end
  end
end

class UserWithForksTransformingIntoAnOrganizationTest < GitHub::TestCase
  skip_with_all_emus

  fixtures do
    @owner = create(:user)

    @user = create(:user, plan: "silver")
    @user.profile_hireable = true
    @user.profile_bio = "Ruby hacker."
    @user.profile_name = "The Dude"
    create(:public_key, user: @user)
    @user.save

    3.times do
      @user.add_email(Faker::Internet.email)
    end
    assert_equal 4, @user.emails.size

    @user_email = @user.email
    @user_billing_email = @user.billing_email
    @user_gravatar_email = @user.gravatar_email
    @old_password = @user.password_hash

    @user2 = create(:user)
    @user3 = create(:user)

    # User 2 forks the repo and grants user 3 collab. When transforming, both of
    # these repos are used to naively name new teams. This failed because the
    # team names weren't unique.
    @repo = create(:private_repository, owner: @user)
    @repo.add_member @user2, @user, false

    @fork = create(:fork_repository, forker: @user2, fork_repo: @repo)
    @fork.add_member @user3
  end

  test "grants admin permission to org owners on forks" do
    Organization.transform!(@user, @owner)

    assert_able @owner, :admin, @repo
    assert_able @owner, :admin, @fork
  end

  test "leaves no abilities between the former user and its forks" do
    ability = Authorization.service.direct_ability_between(actor: @user, subject: @fork)
    refute_nil ability

    Organization.transform!(@user, @owner)

    refute Ability.find_by(id: ability.id), "user ability on fork should have been revoked"
  end

end

class UserTransformingIntoAnOrganizationNoCollisionTest < GitHub::TestCase
  skip_with_all_emus

  # See https://github.com/github/coding/issues/1135
  # This is test to demonstrate a polymorphic type confusion bug and to prevent its regression
  test "only user review requests are dismissed, not random team review requests" do
    owner = create(:user, login: "owner", plan: "micro")
    backup_owner = create(:user, login: "backup")
    org = create(:organization, admin: owner)
    org.add_member(backup_owner, action: :admin)
    org.allow_private_repository_forking(actor: owner)

    # This is the key part of data setup, creating a team with the same PK as owner
    team = create(:team, organization: org, privacy: :closed, id: owner.id)
    forker = create(:user)
    rando = create(:user)

    source = create(:private_repository, owner: org, name: "source", from_example: :review_comment_fork)
    source.add_team team, action: :write
    source.add_member forker, action: :write

    fork = create(:fork_repository, forker: forker, fork_repo: source, from_example: :review_comment_fork)

    issue = create(:issue, user: forker, repository: source)
    pull =
      create(:pull_request,
        repository: source,
        base_repository: source,
        base_user: source.owner,
        base_ref: "master",
        head_repository: fork,
        head_user: fork.owner,
        head_ref: "topic",
        issue: issue,
        user: forker,
      )
    issue.pull_request = pull

    request = pull.review_requests.create!(reviewer: owner)
    team_request = pull.review_requests.create!(reviewer: team)

    new_owner = create(:user, login: "new-owner", plan: "silver")
    Organization.transform!(owner, new_owner, { plan: "silver" })
    assert request.reload.dismissed?, "Review requests should be dismissed when a user transforms."
    refute team_request.reload.dismissed?, "Team review requests that happen to have the same reviewer_id as a transforming user should not be dismissed."
  end
end

class UserTransformingIntoAPerSeatOrganizationTest < GitHub::TestCase
  skip_with_all_emus

  fixtures do
    @owner = create(:user)

    @user = create(:user, plan: "medium")
    @user.profile_hireable = true
    @user.profile_bio = "Ruby hacker."
    @user.profile_name = "RH"
    create(:public_key, user: @user)
    @user.save

    3.times do
      @user.add_email(Faker::Internet.email)
    end
    assert_equal 4, @user.emails.size

    @user_email = @user.email
    @user_billing_email = @user.billing_email
    @user_gravatar_email = @user.gravatar_email
    @old_password = @user.password_hash

    @user2 = create(:user)
    @user3 = create(:user)
    @user4 = create(:user)
    @user5 = create(:user)
    @user6 = create(:user)
    @user7 = create(:user)

    @user.follow(@user2)
    @user.follow(@user4)
    @user3.follow(@user)

    @repo = create(:private_repository, owner: @user)
    @repo2 = create(:repository, owner: @user)
    @user.unwatch_repo(@repo2)
    @repo3 = create(:private_repository, owner: @user)
    @repo4 = create(:private_repository, owner: @user)
    @repo5 = create(:public_repository, owner: @user)

    # collaborating repos and organizations
    @collab_org = create(:organization)
    @team = create :team, organization: @collab_org
    @team.add_member @user
    @collab_repo = create(:repository)
    @collab_repo.add_member @user, @collab_repo.owner, false

    @unowned_repo = create(:repository)
    @user.watch_repo(@unowned_repo)

    @repo.add_member(@user2, @user, false)
    @repo.add_member(@user3, @user, false)
    @repo.add_member(@user6, @user, false)
    @repo.add_member(@user7, @user, false)
    @repo3.add_member(@user2, @user, false)
    @repo3.add_member(@user3, @user, false)
    @repo4.add_member(@user4, @user, false)

    @forked_private = create(:fork_repository, forker: @user2, fork_repo: @repo)
    @forked_public = create(:fork_repository, forker: @user2, fork_repo: @repo5)
    @forked_by_nonmember_public = create(:fork_repository, forker: @user5, fork_repo: @repo5)

    @user2.watch_repo(@repo)
    assert @user2.watching_repo?(@repo)
  end

  context "::transform!" do
    test "becomes an Organization" do
      org = Organization.transform!(@user, @owner, { plan: "business", seats: 5 })
      assert org.organization?
      assert org.plan.business?
    end

    if GitHub.billing_enabled?
      test "has enough seats to cover all collaborators" do
        org = Organization.transform!(@user, @owner, { plan: "business", seats: 5 })
        assert_equal 6, org.seats
      end
    end
  end
end
