# typed: true
# frozen_string_literal: true

require "test_helper"

class UserDeleteTest < GitHub::TestCase
  include ActionMailer::TestHelper
  include WindbeamTestHelper

  fixtures do
    @staffer   = create(:staff_admin_user, login: "staffer", plan: "medium", email: "staffer@example.com")
    @paid_user = create(:user, login: "paiduser", email: "paid_user@example.com", plan: "medium")
    @janedoe   = create(:user, :with_trade_screening_record, login: "janedoe", email: "janedoe@example.com")
    @repo1     = create(:repository, name: "repo1", owner: @janedoe)
    @contents = [
      { name: "file1.txt", value: "cool" },
      { name: "file2.txt", value: "boom" },
    ]
    @invitation = create(:repository_invitation,
      repository_id: @repo1.id,
      inviter_id: @janedoe.id,
      invitee_id: @paid_user.id,
      permissions: 1,
    )
    @partially_deleted_org = create :organization
    @partially_deleted_org.deleted = true
    @partially_deleted_org.deleted_by = @partially_deleted_org.admins.first.login
    @partially_deleted_org.deleted_at = Time.now
    @partially_deleted_org.save!
  end

  setup do
    @gist1 = Gist::Creator.create!(owner: @janedoe, contents: @contents, public: true)
    stub_windbeam
  end

  context "emails" do
    test "destroying a user deletes any emails and email roles" do
      user_id = @paid_user.id
      email = @paid_user.add_email "another@example.com"
      assert_equal 2, @paid_user.emails.count
      @paid_user.destroy
      assert_equal 0, @paid_user.emails.count
      assert_equal 0, UserEmail.where(user_id: user_id).count
      assert_equal 0, EmailRole.where(user_id: user_id).count
    end

    test "can destroy a user even if they do not have any emails" do
      @janedoe.emails.map { |e| e.delete }
      @janedoe.reload
      assert_equal 0, @janedoe.emails.count
      assert @janedoe.destroy
    end

    test "user's still have their email cached after destroy" do
      email = @paid_user.email
      @paid_user.destroy
      assert_equal email, @paid_user.email
    end

    test "destroying a suspended user sends no deletion confirmation email" do
      user = create(:suspended_user)
      user.destroy

      assert_enqueued_emails 0
    end

    test "destroying a gh_role of staff_delete user sends no deletion confirmation email" do
      user = create(:user, gh_role: "staff_delete")
      user.destroy

      assert_enqueued_emails 0
    end

    test "destroying a spammy user without a dsa_source value sends no deletion confirmation email" do
      user = create(:user)
      user.mark_as_spammy
      user.destroy

      assert_enqueued_emails 0
    end

    unless GitHub.enterprise?

      test "destroying a user sends deletion confirmation email" do
        user = create(:user)
        user.destroy

        # Should send one email to the user and another to the logging address
        assert_enqueued_emails 2
      end

      test "destroying a spammy user with a dsa_source value in a non-Enterprise context sends a statement of reasons email" do
        user = create(:user)
        user.mark_as_spammy(dsa_source: "USER_REPORT", reason: "MISUSE_OF_PII")
        user.destroy

        assert_enqueued_emails 1
      end

    end
  end

  test "cleans up blocks on user delete" do
    user = create(:user)
    user.block(@paid_user)
    id = user.id
    assert_equal [id], @paid_user.ignored_by_ids
    user.destroy
    assert_equal [], @paid_user.reload.ignored_by_ids
  end

  test "destroying a user queues deletion of repositories" do
    @janedoe.destroy
    assert_enqueued_jobs 1, only: [RepositoryOrchestrationJob]
  end

  test "destroying a user removes their marketplace_order_previews" do
    create(:marketplace_order_preview, user: @janedoe)

    assert_difference "@janedoe.marketplace_order_previews.count", -1 do
      @janedoe.destroy
    end
  end

  test "destroying an org removes its marketplace_order_previews" do
    create(:marketplace_order_preview, user: @janedoe)
    org = create(:organization)
    create(:marketplace_order_preview, account: org)

    assert_difference "@janedoe.marketplace_order_previews.count", 0 do
      assert_difference "Marketplace::OrderPreview.count", -1 do
        org.destroy
      end
    end
  end

  test "destroying a user clears their user status" do
    status = create(:user_status, user: @janedoe)

    assert_difference "UserStatus.count", -1 do
      @janedoe.destroy
    end

    refute UserStatus.exists?(status.id)
  end

  test "destroying an org clears any org-restricted user statuses for the org" do
    org1 = create(:organization)
    org1.add_member(@janedoe)

    org2 = create(:organization)
    org2.add_member(@staffer)
    org2.add_member(@paid_user)

    status1 = create(:user_status, user: @staffer, organization: org2)
    status2 = create(:user_status, user: @janedoe, organization: org1)
    status3 = create(:user_status, user: @paid_user, organization: org2)

    assert_difference "UserStatus.count", -2 do
      org2.destroy
    end

    refute UserStatus.exists?(status1.id),
      "should have deleted org-restricted status for the deleted org"
    assert UserStatus.exists?(status2.id),
      "should not have deleted org-restricted status for a different org"
    refute UserStatus.exists?(status3.id),
      "should have deleted all the org-restricted statuses for the deleted org"
  end

  test "destroying a user cancels their plan" do
    create :billing_plan_subscription, :zuora, user: @janedoe

    assert_enqueued_jobs 1, only: CloseOutZuoraSubscriptionJob do
      @janedoe.destroy
    end
  end

  test "destroying a user cancels their braintree subscription" do
    user = create(:user, plan: GitHub::Plan.bronze)
    plan_subscription = create(:billing_plan_subscription, user: user)
    user.destroy

    assert_raises ActiveRecord::RecordNotFound do
      plan_subscription.reload
    end
  end

  test "destroying a user queues related repos for deletion" do
    @janedoe.stubs(:cancel_subscription)
    @janedoe.destroy

    assert_enqueued_jobs 1, only: [RepositoryOrchestrationJob]
  end

  test "destroying a user kicks off Repository removal" do
    # We want to make sure user delete fires the correct
    # Repository#remove sequence
    Repository.any_instance.expects(:remove).times(@janedoe.repositories.size)
    @janedoe.stubs(:cancel_subscription)
    @janedoe.destroy
  end

  test "destroying a user soft-deletes associated Gists" do
    gists = @janedoe.gists.all

    gists.each do |gist|
      assert_predicate gist, :active?
    end

    @janedoe.destroy

    gists.reload

    gists.each do |gist|
      assert gist.deleted?
      refute gist.active?
    end
  end

  test "rolling back the deletion does not leave gists in a broken state" do
    gists = @janedoe.gists.all

    User.transaction do
      @janedoe.destroy
      raise ActiveRecord::Rollback
    end

    gists.each do |gist|
      assert_predicate gist.reload, :active?
      assert Gist.exists?(id: gist.id)
      assert_predicate gist, :exists_on_disk?
    end
  end

  test "removes all associated user emails" do
  end

  test "destroying a user removes followers" do
    @staffer.follow(@janedoe)
    assert_equal 1, User.find(@staffer.id).following_count(viewer: nil)

    User::FollowDependency.stub_const(:FOLLOW_CALCULATION_INTERVAL_IN_SECONDS, 0) do
      perform_enqueued_jobs(only: [CalculateFolloweringsCountJob]) { @janedoe.destroy }
    end
    assert_equal 0, User.find(@staffer.id).following_count(viewer: nil)
  end

  test "destroying a user unfollows others" do
    @janedoe.follow(@staffer)
    assert_equal 1, User.find(@staffer.id).followers_count(viewer: nil)

    User::FollowDependency.stub_const(:FOLLOW_CALCULATION_INTERVAL_IN_SECONDS, 0) do
      perform_enqueued_jobs(only: [CalculateFolloweringsCountJob]) { @janedoe.destroy }
    end
    assert_equal 0, User.find(@staffer.id).followers_count(viewer: nil)
  end

  test "destroying a user deletes their stars" do
    @paid_user.star(@repo1)
    @janedoe.star(@repo1)

    assert_difference "Star.count", -1 do
      @janedoe.destroy
    end
  end

  test "destroying a user deletes their review requests" do
    @repo1.add_member @paid_user, action: :write

    example_repo :simple, @repo1
    issue = create(:issue, user: @paid_user, repository: @repo1)

    pull = create(:pull_request,
      repository: @repo1,
      base_ref: "master",
      head_ref: "cr-line-endings",
      issue: issue,
    )

    pull.review_requests.create!(reviewer: @janedoe)

    assert_difference "ReviewRequest.count", -1 do
      @janedoe.destroy
    end
  end

  test "destroying a user deletes their repository invitations" do
    @paid_user.destroy
    assert_nil RepositoryInvitation.find_by(id: @invitation.id)
  end

  test "destroying a user deletes their business support entitlements" do
    customer = create :customer, payment_method: build(:paypal_payment_method, user: create(:user), customer: nil)
    business = create :business, :volume_licensed, owners: [create(:user)], organizations: [create(:organization)], customer: customer

    user = create(:user)
    business.organizations.first.add_member(user)
    business.add_support_entitlee(user, actor: nil)
    assert_equal 1, business.support_entitlees.count
    user.destroy
    assert_equal 0, business.support_entitlees.count
  end

  test "destroying a user when they have authored CommitComments on their own repo" do
    example_repo :simple, @repo1
    commit = @repo1.heads.find("master").target
    commit_comment = create(:commit_comment, repository: @repo1,
                                        commit_id: commit.oid,
                                        user: @janedoe)

    @janedoe.destroy

    assert_nil CommitComment.find_by(id: commit_comment.id)
  end

  test "preemptively deletes public_org_members join table entries" do
    org = create(:organization)
    org.add_member(@janedoe)
    org.publicize_member(@janedoe)
    assert_difference('Organization.connection.execute("select * from public_org_members").rows.size', -1) do
      @janedoe.destroy
    end
  end

  test "destroying a user owning an organization fails with error" do
    org = create(:organization, admin: @janedoe)
    user = create(:user)
    org.add_admin(user)
    refute @janedoe.destroy
    assert_equal "You must transfer or delete all owned organizations", @janedoe.errors[:organizations].first
  end unless GitHub.enterprise?

  test "does not raise an error if the user owns only a soft-deleted organization" do
    GitHub.flipper[:soft_delete_organization].enable

    org = create(:organization, admin: @janedoe)
    org.soft_delete!
    assert @janedoe.destroy
  end

  if GitHub.mailchimp_enabled?
    test "destroying a user deletes them from Mailchimp" do
      user = create(:user)
      user.destroy
      assert_enqueued_jobs 1, only: MailchimpDeleteJob
    end
  else
    test "destroying a user doesn't make a call to MailChimp" do
      user = create(:user)
      user.destroy
      assert_no_enqueued_jobs only: MailchimpDeleteJob
    end
  end

  context "notification subscriptions" do
    test "removes all notification subscriptions" do
      perform_enqueued_jobs(only: [Newsies::DeleteAllForUserJob]) do
        user = create(:user)
        repo = create(:repository)
        user.watch_repo repo
        GitHub.newsies.auto_subscribe(user, repo, true)
        assert GitHub.newsies.subscription_status(user, repo).valid?
        user.destroy
        refute GitHub.newsies.subscription_status(user, repo).valid?
      end
    end
  end

  class AsyncDestroyTest < GitHub::TestCase
    include ApiProgrammaticGrantHelpers
    include WindbeamTestHelper
    include GitHub::LoggerHelper

    setup do
      stub_windbeam
    end

    fixtures do
      @user = create(:user)

      @repo = create(:repository, owner: @user)

      @user_owned_app = create(:oauth_application, user: @user)
      @other_app = create(:oauth_application)

      token_owner = create(:user)
      @user_owned_app_token = create(:oauth_access, user: token_owner, application: @user_owned_app)
      @other_app_token = create(:oauth_access, user: token_owner, application: @other_app)
    end

    test "does nothing if deletion is not permitted" do
      @user.trade_controls_restriction.full!
      refute_predicate @user, :permit_deletion?
      refute_predicate @user, :deleted?

      perform_enqueued_jobs(only: [UserDeleteJob]) do
        @user.async_destroy
      end

      refute_predicate @user, :deleted?
    end

    test "marks the user as deleted if deletion is not permitted but skip_permitted_check is true" do
      @user.trade_controls_restriction.full!
      refute_predicate @user, :permit_deletion?
      refute_predicate @user, :deleted?

      perform_enqueued_jobs(only: [UserDeleteJob]) do
        @user.async_destroy(skip_permitted_check: true)
      end

      assert_predicate @user, :deleted?
    end

    test "marks the user as deleted" do
      expected_time = Time.now.change(usec: 0)

      Timecop.freeze(expected_time) do
        @user.async_destroy
      end

      assert_predicate @user, :deleted?
      assert_equal expected_time, @user.deleted_at
    end

    test "records the login of the user who triggered the deletion" do
      actor = create(:user)

      @user.async_destroy(actor)

      assert_equal actor.login, @user.deleted_by
    end

    test "does not record deleter information if no actor is given" do
      @user.async_destroy

      assert_nil @user.deleted_by
    end

    test "removes all owned OAuth applications" do
      perform_enqueued_jobs(only: [UserDeleteJob]) do
        @user.async_destroy
      end

      refute OauthApplication.exists?(@user_owned_app.id)
      assert OauthApplication.exists?(@other_app.id)
    end

    test "removes all tokens for owned OAuth applications" do
      perform_enqueued_jobs(only: [UserDeleteJob]) do
        @user.async_destroy
      end

      refute OauthAccess.exists?(@user_owned_app_token.id)
      assert OauthAccess.exists?(@other_app_token.id)
    end

    test "removes user programmatic access and its dependencies" do
      org = create(:organization)
      org.add_member(@user)

      pending_pat = make_user_programmatic_access_with_grant_request(
        actor: @user, target: org, permissions: { "members" => :read }
      )

      request_id = pending_pat.grant_request.id

      perform_enqueued_jobs(only: [UserDeleteJob, DestroyDependentRecordsJob]) do
        @user.async_destroy
      end

      refute OrganizationProgrammaticAccessGrantRequest.exists?(request_id)
    end

    test "queues dependent repositories and their associations for deletion" do
      @user.async_destroy

      perform_enqueued_jobs(only: [UserDeleteJob])
      assert_enqueued_jobs 1, only: [RepositoryOrchestrationJob]
    end

    test "removes all client application installation records" do
      @user.enable_desktop_app(:mac)

      client_application_set = ClientApplicationSet.new(@user.id)

      assert_changes -> { client_application_set.include?(:github_desktop) }, from: true, to: false do
        perform_enqueued_jobs(only: [UserDeleteJob]) do
          @user.async_destroy
        end
      end
    end

    test "logs when processing callbacks" do
      perform_enqueued_jobs(only: [UserDeleteJob]) do
        expected_payload = {
          "code.namespace" => "DeleteRepositoryOrchestration",
          "Body" => "Orchestration step started",
          "gh.repo.id" => @repo.id
        }
        assert_logged(**expected_payload) do
          @user.async_destroy
        end
      end
    end

    if GitHub.spamminess_check_enabled?
      test "delays deletion if recently updated UGC" do
        GitHub.flipper[:delay_user_deletion_for_spam_checks].enable

        create(:issue,
          user: @user,
          created_at: 1.month.ago,
          updated_at: 12.hours.ago,
        )

        travel_to(Time.now) do
          perform_at = User::SpamDependency::DELETION_DELAY.from_now

          assert_enqueued_with(job: UserDeleteJob, at: perform_at, args: [@user.id, @user.login]) do
            @user.async_destroy
          end
        end
      end

      test "does not delay deletion for user without UGC in last 24 hours" do
        GitHub.flipper[:delay_user_deletion_for_spam_checks].enable

        create(:issue,
          user: @user,
          created_at: 1.month.ago,
          updated_at: 2.days.ago,
        )

        assert_enqueued_with(job: UserDeleteJob, args: [@user.id, @user.login]) do
          @user.async_destroy
        end
      end

      test "does not delay deletion for EMU" do
        GitHub.flipper[:delay_user_deletion_for_spam_checks].enable

        emu = create(:emu)
        create(:issue,
          user: emu,
          created_at: 1.month.ago,
          updated_at: 12.hours.ago,
        )

        assert_enqueued_with(job: UserDeleteJob, args: [emu.id, emu.login]) do
          emu.async_destroy(skip_permitted_check: true)
        end
      end

      test "does not delay deletion if feature flag disabled" do
        GitHub.flipper[:delay_user_deletion_for_spam_checks].disable

        create(:issue,
          user: @user,
          created_at: 1.month.ago,
          updated_at: 12.hours.ago,
        )

        assert_enqueued_with(job: UserDeleteJob, args: [@user.id, @user.login]) do
          @user.async_destroy
        end
      end
    else
      test "does not enqueue with delay if spam checks are disabled" do
        GitHub.flipper[:delay_user_deletion_for_spam_checks].enable

        create(:issue,
          user: @user,
          created_at: 1.month.ago,
          updated_at: 12.hours.ago,
        )

        assert_enqueued_with(job: UserDeleteJob, args: [@user.id, @user.login]) do
          @user.async_destroy
        end
      end
    end
  end

  if GitHub.spamminess_check_enabled?
    context "#delete_spam_content" do
      test "deletes issues with PRs from deleted spammy users" do
        spammer    = create(:user)
        spam_repo  = create(:repository, name: "spam", owner: spammer, from_example: :simple)
        spam_issue = create(:issue, repository: spam_repo, user: spammer)
        spam_pr    = create(:pull_request,
          repository: spam_repo,
          base_ref: "master",
          head_ref: "cr-line-endings",
          issue: spam_issue,
        )

        spammer.mark_as_spammy(
          actor: @janedoe,
          reason: "Definitely a spammer",
        )
        spammer.destroy

        assert_nil Issue.find_by(id: spam_issue.id)
        assert_nil PullRequest.find_by(id: spam_pr.id)
        assert_nil User.find_by(id: spammer.id)
      end
    end
  end

  context "#permit_deletion?" do
    test "returns false when a legal hold exists even for staff actor" do
      assert @janedoe.permit_deletion?(@janedoe)
      assert @janedoe.permit_deletion?(@staffer)

      @janedoe.place_legal_hold(actor: @staffer)
      assert @janedoe.reload.legal_hold?
      refute @janedoe.permit_deletion?(@janedoe)
      refute @janedoe.permit_deletion?(@staffer)

      @janedoe.clear_legal_hold(actor: @staffer)
      refute @janedoe.reload.legal_hold?
      assert @janedoe.permit_deletion?(@janedoe)
      assert @janedoe.permit_deletion?(@staffer)
    end

    test "returns false for system account" do
      @janedoe.stubs(system_account?: true)

      refute @janedoe.permit_deletion?(@janedoe)
      refute @janedoe.permit_deletion?(@staffer)
    end

    test "returns false when trade controls restrictions exists with actor as self" do
      @janedoe.trade_controls_restriction.full!
      refute @janedoe.permit_deletion?
    end

    test "returns true when trade controls restrictions exists with actor as site admin" do
      @janedoe.trade_controls_restriction.full!
      assert @janedoe.permit_deletion?(@staffer)
    end

    test "returns false when trade screening restrictions exists with actor as self" do
      @janedoe.trade_screening_record.hit_in_review!
      refute_predicate @janedoe, :permit_deletion?
    end

    test "returns false when trade screening restrictions exists with actor as site admin" do
      @janedoe.trade_screening_record.hit_in_review!
      refute @janedoe.permit_deletion?(@staffer)
    end

    test "returns false when IdP manages user deletion with actor as self" do
      @janedoe.stubs(:managed_user_deletion_disabled?).returns(true)
      refute @janedoe.permit_deletion?(@janedoe)
    end

    test "returns true when IdP manages user deletion with actor as site admin" do
      @janedoe.stubs(:managed_user_deletion_disabled?).returns(true)
      assert @janedoe.permit_deletion?(@staffer)
    end
  end

  context "#cannot_delete_reason" do
    test "returns nil when deletion permitted" do
      assert @janedoe.permit_deletion?(@janedoe)
      assert_nil @janedoe.cannot_delete_reason(@janedoe)
    end

    test "returns :legal_hold when expected" do
      @janedoe.stubs(:legal_hold?).returns(true)
      assert_equal :legal_hold, @janedoe.cannot_delete_reason(@janedoe)
      assert_equal :legal_hold, @janedoe.cannot_delete_reason(@staffer)
    end

    test "returns :system_account when expected" do
      @janedoe.stubs(:system_account?).returns(true)
      assert_equal :system_account, @janedoe.cannot_delete_reason(@janedoe)
    end

    test "returns nil when actor is site admin" do
      assert @janedoe.permit_deletion?(@staffer)
      assert_nil @janedoe.cannot_delete_reason(@staffer)
    end

    test "returns :trade_restrictions when expected" do
      @janedoe.stubs(:has_any_trade_restrictions?).returns(true)
      assert_equal :trade_restrictions, @janedoe.cannot_delete_reason(@janedoe)
    end

    test "returns :trade_restrictions for trade controls restricted user" do
      @janedoe.stubs(:has_any_trade_restrictions?).returns(true)
      assert_equal :trade_restrictions, @janedoe.cannot_delete_reason(@janedoe)
    end

    test "returns :trade_restrictions for trade screening restricted user" do
      @janedoe.trade_screening_record.stubs(:delete_restricted?).returns(true)
      assert_equal :trade_restrictions, @janedoe.cannot_delete_reason(@janedoe)
    end

    test "returns :spammy when expected" do
      @janedoe.stubs(:spammy?).returns(true)
      @janedoe.stubs(:spammy_deleting_overridden?).returns(false)
      assert_equal :spammy, @janedoe.cannot_delete_reason(@janedoe)
    end

    test "returns nil when spammy but spammy deletion is overridden" do
      @janedoe.stubs(:spammy?).returns(true)
      @janedoe.stubs(:spammy_deleting_overridden?).returns(true)
      assert_nil @janedoe.cannot_delete_reason(@janedoe)
    end

    test "returns :managed_user when IdP manages user deletion" do
      @janedoe.stubs(:managed_user_deletion_disabled?).returns(true)
      assert_equal :managed_user, @janedoe.cannot_delete_reason(@janedoe)
    end

    test "returns nil when IdP manages user deletion but actor is site admin" do
      @janedoe.stubs(:managed_user_deletion_disabled?).returns(true)
      assert_nil @janedoe.cannot_delete_reason(@staffer)
    end

    if GitHub.sponsors_enabled?
      test "returns :sponsorable when user has active sponsorships" do
        sponsors_listing = create(:sponsors_listing, :approved, sponsorable: @janedoe)
        create(:sponsorship, sponsorable: @janedoe)
        refute_empty @janedoe.sponsorships_as_sponsorable
        assert_equal :sponsorable, @janedoe.cannot_delete_reason(@janedoe)
      end

      test "returns :sponsorable for site admin when user has active sponsorships" do
        sponsors_listing = create(:sponsors_listing, :approved, sponsorable: @janedoe)
        create(:sponsorship, sponsorable: @janedoe)
        refute_empty @janedoe.sponsorships_as_sponsorable
        assert_equal :sponsorable, @janedoe.cannot_delete_reason(@staffer)
      end

      test "returns :sponsors_listing_not_deletable when user was previously sponsored" do
        sponsors_listing = create(:sponsors_listing, :approved, sponsorable: @janedoe)
        sponsorship = create(:sponsorship, sponsorable: @janedoe)
        sponsorship.cancel(actor: @janedoe, force: true)
        sponsors_listing.redraft!
        refute_empty @janedoe.reload.sponsorships_as_sponsorable
        assert_equal :sponsors_listing_not_deletable, @janedoe.cannot_delete_reason(@staffer)
      end

      test "returns nil if previously sponsored but listing has since been deleted" do
        sponsors_listing = create(:sponsors_listing, :approved, sponsorable: @janedoe)
        sponsorship = create(:sponsorship, sponsorable: @janedoe)
        refute_empty @janedoe.sponsorships_as_sponsorable

        sponsorship.cancel(actor: @janedoe, force: true)
        sponsors_listing.redraft!
        sponsors_listing.deletion_confirmation = @janedoe.display_login
        sponsors_listing.destroy!

        assert_nil @janedoe.reload.cannot_delete_reason(@janedoe)
      end

      test "returns nil if user has a draft listing but has never been sponsored" do
        sponsors_listing = create(:sponsors_listing, :draft, sponsorable: @janedoe)
        assert_empty @janedoe.sponsorships_as_sponsorable
        assert_nil @janedoe.cannot_delete_reason(@janedoe)
      end
    end

    test "returns nil if user does not have a sponsors listing" do
      assert_nil @janedoe.sponsors_listing
      assert_nil @janedoe.cannot_delete_reason(@janedoe)
    end
  end

  context "#mark_not_deleted" do
    test "returns false if user is not marked as deleted" do
      org = create :organization
      refute_predicate org, :deleted?

      refute org.mark_not_deleted

      refute_predicate org, :deleted?
    end

    test "returns true if partially deleted user successfully marked as not deleted" do
      assert_predicate @partially_deleted_org.reload, :deleted?

      assert @partially_deleted_org.mark_not_deleted

      refute_predicate @partially_deleted_org.reload, :deleted?
      assert_nil @partially_deleted_org.deleted_at
      assert_nil @partially_deleted_org.deleted_by
    end

    test "instruments an audit entry if successful" do
      assert_predicate @partially_deleted_org.reload, :deleted?
      events = subscribe "staff.mark_user_not_deleted"

      assert @partially_deleted_org.mark_not_deleted

      refute_predicate @partially_deleted_org.reload, :deleted?
      assert event = events.pop, "a staff.mark_user_not_deleted event was expected"
      expected_payload = {
        user: @partially_deleted_org.to_s,
        user_id: @partially_deleted_org.id,
      }
      assert_equal expected_payload, event.payload
    end

    test "removes JobStatus if one exists for the user" do
      error = StandardError.new "whatever"
      DestroyUserCallbacks.any_instance.expects(:remove_followers).with(@partially_deleted_org).raises(error)

      assert_raises StandardError do
        UserDeleteJob.perform_now(@partially_deleted_org.id, @partially_deleted_org.login)
      end
      assert UserDeleteJob.status(@partially_deleted_org.id)
      assert_predicate @partially_deleted_org.reload, :deleted?

      assert @partially_deleted_org.mark_not_deleted

      refute_predicate @partially_deleted_org.reload, :deleted?
      assert_nil @partially_deleted_org.deleted_at
      assert_nil @partially_deleted_org.deleted_by
      assert_nil UserDeleteJob.status(@partially_deleted_org.id)
    end

    test "returns false if partially deleted user cannot be marked as not deleted" do
      assert_predicate @partially_deleted_org.reload, :deleted?

      @partially_deleted_org.stubs(:save).returns(false)
      refute @partially_deleted_org.mark_not_deleted

      assert_predicate @partially_deleted_org.reload, :deleted?
    end
  end
end
