# typed: false
# frozen_string_literal: true

require "test_helper"

class UserDormancyTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @actor = create(:user)
    @long_ago = (GitHub.dormancy_threshold + 1.month).ago.freeze
    @recently = (GitHub.dormancy_threshold - 15.days).ago.freeze

    Timecop.freeze(@long_ago) do
      @user = create(:user)
    end

    @business = create(:business)
  end

  setup do
    # If this flag is enabled we won't get stratocaster events from activity, which we rely
    # on to calculate dormancy
    GitHub.flipper[:discard_stratocaster_fanout].disable
    GitHub.reset_stratocaster

    # This query only works properly on dotcom, we have to stub it out here
    Audit::Driftwood::Query.stubs(:get_business_user_dormancy_latest_timestamp).returns(nil)
  end

  def is_active_time?(time)
    time.present? && time > GitHub.dormancy_threshold.ago
  end

  context "#dormant?" do
    test "is true" do
      assert @user.dormant?
    end

    test "result is memoised" do
      # User#dormant? makes expensive calls, so we memoise the results to avoid
      # unnecessary performance penalties.
      assert @user.expects(:exempt_from_dormancy?).once
      assert @user.expects(:recently_active?).once
      assert @user.dormant?
      assert @user.expects(:exempt_from_dormancy?).never
      assert @user.expects(:recently_active?).never
      assert @user.dormant?
    end

    unless GitHub.enterprise?
      test "is false if exempt from dormancy checks" do
        @user.update plan: "Micro"
        refute @user.dormant?
      end
    end

    test "is false if user is active" do
      @user.update created_at: @recently
      refute @user.dormant?
    end

    if GitHub.enterprise?
      test "is true when dormancy threshold is re-configured" do
        GitHub.set_enterprise_dormancy_threshold_days(60, @actor)
        @user.update created_at: 3.months.ago
        assert @user.dormant?
      end
    end
  end

  context "#exempt_from_dormancy?" do
    if GitHub.enterprise?
      test "is always false" do
        create :personal_token_oauth_access, user: @user
        refute @user.exempt_from_dormancy?
      end
    else
      test "is false" do
        refute @user.exempt_from_dormancy?
      end

      # These tests need to be updated as part of a Project Phoenix change to be
      # aware of plan history as the rule here should be "have ever been (past
      # or current) on a payment plan"
      #
      # see https://github.com/github/pe-phoenix/issues/41 for more information
      if GitHub.billing_enabled?
        test "is true if paying" do
          @user.update plan: "Micro"
          assert @user.exempt_from_dormancy?
        end

        test "is false if on paid plan and disabled" do
          @user.update plan: "Micro", disabled: true
          refute @user.exempt_from_dormancy?
        end

        test "is false if currently on free plan" do
          @user.update plan: "Free"
          refute @user.exempt_from_dormancy?
        end
      end

      test "is true if user has two-factor enabled" do
        @user.update two_factor_credential: create(:two_factor_credential)
        assert @user.exempt_from_dormancy?
      end

      test "is true if member of org" do
        Timecop.freeze(@long_ago) do
          org = create :organization, admin: @user, plan: "Free"
        end

        assert @user.exempt_from_dormancy?
      end

      test "is true if user has a token" do
        create :personal_token_oauth_access, user: @user
        assert @user.exempt_from_dormancy?
      end

      test "is true if user has authorized an oauth app" do
        make_trusted_oauth_apps_owner
        create(:oauth_access, user: @user)
        assert @user.exempt_from_dormancy?
      end

      test "is true if user has a public key" do
        create(:public_key, user: @user)
        assert @user.exempt_from_dormancy?
      end

      test "is true if user has collaborator rights to a repo" do
        create(:repository).add_member @user
        assert @user.exempt_from_dormancy?
      end

      test "is true if user has a dormant public non-fork repo" do
        Timecop.freeze(@long_ago) do
          create(:public_repository, owner: @user)
        end

        assert @user.exempt_from_dormancy?
      end

      test "is true if user has a dormant private non-fork repo" do
        Timecop.freeze(@long_ago) do
          create(:private_repository, owner: @user)
        end

        assert @user.exempt_from_dormancy?
      end
      test "is true when strict if the user has public packages" do
        Timecop.freeze(@long_ago) do
          repo = create(:public_repository, owner: @user)
          package = repo.packages.create(name: "an-old-package", package_type: :rubygems)
        end
        assert @user.exempt_from_dormancy?(strict: true)
      end
      test "is true when strict if the user belongs to an active organization" do
        org = create :organization, admin: @user, plan: "Free"
        assert @user.exempt_from_dormancy?(strict: true)
      end
      test "is false when strict if the user belongs to a dormant organization" do
        Timecop.freeze(@long_ago) do
          org = create :organization, admin: @user, plan: "Free"
        end
        assert !@user.exempt_from_dormancy?(strict: true)
      end
      test "is true when strict if the user has made an issue comment" do
        Timecop.freeze(@long_ago) do
          repo = create(:repository, owner: @actor, has_discussions: true)
          repo.add_member(@user)
          @issue = create :issue, repository: repo
        end
        create :issue_comment, issue: @issue, user: @user
        assert @user.exempt_from_dormancy?(strict: true)
      end
      test "is true when strict if the user has made a commit comment" do
        Timecop.freeze(@long_ago) do
          @repo = create(:repository, owner: @actor, has_discussions: true)
          @repo.add_member(@user)
          @commit = "c3956841a7cb7e8ba4a6fd923568d86958f01574"
          @comment = create :commit_comment, user: @actor, repository: @repo,
                      position: 0, path: "color.js", commit_id: @commit
        end
        comment = create :commit_comment, user: @user, repository: @repo, commit_id: @commit, body: "body"
        assert @user.exempt_from_dormancy?(strict: true)
      end
      test "is true when strict if the user has made an issue" do
        Timecop.freeze(@long_ago) do
          repo = create(:repository, owner: @actor, has_discussions: true)
          repo.add_member(@user)
          @issue = create :issue, repository: repo, user: @user
        end
        assert @user.exempt_from_dormancy?(strict: true)
      end
      test "is true when strict if the user has public gists" do
        Timecop.freeze(@long_ago) do
          gist = create :gist, owner: @user, repo_name: "pub", public: true
        end
        assert @user.exempt_from_dormancy?(strict: true)
      end
      test "is true when strict if the user has secret gists" do
        Timecop.freeze(@long_ago) do
          gist = create :gist, owner: @user, repo_name: "pub", public: false
        end
        assert @user.exempt_from_dormancy?(strict: true)
      end
      test "is true when strict if the user has been recently invited to an organization" do
        org = create(:organization)
        org.add_admin(@actor)
        invite = org.invite(email: @user.email, inviter: @actor)
        with_es_refresh do
          @audit_entry = es_log_as_hit(
            :_document_id => "audit",
            :@timestamp => 1542219809799,
            :action => "org.invite_member",
            :actor => @actor.login,
            :actor_id => @actor.id,
            :user => @user.login,
            :user_id => @user.id,
            :org => org.login,
            :org_id => org.id,
            :data => {
              spammy: true,
              email: "user@github.com",
              invitation_id: invite.id,
            },
          )
        end
        assert @user.exempt_from_dormancy?(strict: true)
      end
      test "is false when strict if the user hasn't been recently invited to an organization" do
        org = create(:organization)
        org.add_admin(@actor)
        invite = org.invite(email: @user.email, inviter: @actor)
        with_es_refresh do
          @audit_entry = es_log_as_hit(
            :_document_id => "audit",
            :@timestamp => 1542219809799,
            :action => "org.invite_member",
            :actor => @actor.login,
            :actor_id => @actor.id,
            :user => @actor.login,
            :user_id => @actor.id,
            :org => org.login,
            :org_id => org.id,
            :data => {
              spammy: true,
              email: "user@github.com",
              invitation_id: invite.id,
            },
          )
        end
        assert !@user.exempt_from_dormancy?(strict: true)
      end
    end
  end

  context "#dormant_within_business?" do
    test "defaults to true" do
      assert @user.dormant_within_business?(business: @business)
    end

    test "returns false if the user has had some activity" do
      # being recently created counts as activity, see the tests for #recent_activity_within_business
      @user.update created_at: @recently
      refute @user.dormant_within_business?(business: @business)
    end
  end

  context "#recent_activity_within_business" do
    test "defaults to nil" do
      assert_nil @user.recent_activity_within_business(business: @business)
    end

    test "returns [:created_at, time] if the user was created recently" do
      @user.update created_at: @recently
      (reason, _) = @user.recent_activity_within_business(business: @business)
      assert_equal :created_at, reason
    end

    test "returns nil if user was created more than a year ago" do
      @user.update created_at: @long_ago
      assert_nil @user.recent_activity_within_business(business: @business)
    end

    if GitHub.billing_enabled?
      test "is [:billing_transaction, time] if user has a recent transaction" do
        plan_subscription = create(:billing_plan_subscription, :business_owned, customer: @business.customer)
        transaction = create(:billing_transaction, user: @user, plan_subscription: plan_subscription, customer: @business.customer)
        (reason, _) = @user.recent_activity_within_business(business: @business)
        assert_equal :billing_transaction, reason
      end

      test "is nil if user has a recent transaction for a different business" do
        create(:billing_transaction, user: @user)

        assert_nil @user.recent_activity_within_business(business: @business)
      end

      test "is nil if user only has old transactions" do
        Timecop.freeze(@long_ago) do
          plan_subscription = create(:billing_plan_subscription, :business_owned, customer: @business.customer)
          transaction = create(:billing_transaction, user: @user, plan_subscription: plan_subscription, customer: @business.customer)
          create(:billing_transaction, user: @user, plan_subscription: plan_subscription)
        end

        assert_nil @user.recent_activity_within_business(business: @business)
      end
    end

    test "returns [:stratocaster_event, time] if user has a recent stratocaster event for the business" do
      jobs = [ProcessEventJob, UpdateEventFeedsJob]
      org = create(:organization, business: @business)
      repo = create(:repository, owner: org)
      perform_enqueued_jobs(only: jobs) { create(:issue, :with_instrumentation, :wait_for_orchestration, repository: repo, user: @user) }
      (reason, _) = @user.recent_activity_within_business(business: @business)
      assert_equal :stratocaster_event, reason
    end

    test "nil if the event is not recent" do
      jobs = [ProcessEventJob, UpdateEventFeedsJob]
      org = create(:organization, business: @business)
      repo = create(:repository, owner: org)
      Timecop.freeze(@long_ago) do
        perform_enqueued_jobs(only: jobs) { create(:issue, :with_instrumentation, :wait_for_orchestration, repository: repo, user: @user) }
      end

      assert_nil @user.recent_activity_within_business(business: @business)
    end

    test "returns nil if the event is not for the business" do
      jobs = [ProcessEventJob, UpdateEventFeedsJob]
      perform_enqueued_jobs(only: jobs) { create(:issue, :with_instrumentation, :wait_for_orchestration, user: @user) }
      assert_nil @user.recent_activity_within_business(business: @business)
    end

    test "returns [:audit_log_event, time] if the user has a recent audit log event" do
      # this overrides the .stub call in the main setup block
      Audit::Driftwood::Query.stubs(:get_business_user_dormancy_latest_timestamp).returns(@recently)

      (reason, _) = @user.recent_activity_within_business(business: @business)
      assert_equal :audit_log_event, reason
    end

    test "will try to query the audit service a total of 3 times if the service raises an error" do
      # this overrides the .stub call in the main setup block
      Audit::Driftwood::Query.stubs(:get_business_user_dormancy_latest_timestamp)
        .raises(Driftwood::TwirpUtil::Error)
        .then.raises(Faraday::TimeoutError)
        .then.returns(@recently)

      (reason, _) = @user.recent_activity_within_business(business: @business)
      assert_equal :audit_log_event, reason
    end

    test "will return [:driftwood_error, time] if the service returns an error the third time" do
      # this overrides the .stub call in the main setup block
      Audit::Driftwood::Query.stubs(:get_business_user_dormancy_latest_timestamp)
        .raises(StandardError)

      (reason, _) = @user.recent_activity_within_business(business: @business)
      assert_equal :driftwood_error, reason
    end
  end

  context "#recently_active?" do
    test "is false" do
      refute @user.recently_active?
    end

    test "is true if user was created recently" do
      @user.update created_at: @recently
      assert @user.recently_active?
    end

    test "is false if user was created more than a year ago" do
      @user.update created_at: @long_ago
      refute @user.recently_active?
    end

    if GitHub.billing_enabled?
      test "is true if user has a recent transaction" do
        create :billing_transaction, user: @user
        assert @user.recently_active?
      end

      test "is false if user only has old transactions" do
        Timecop.freeze(@long_ago) do
          create :billing_transaction, user: @user
        end
        refute @user.recently_active?
      end
    end

    test "is true if user has a recent session" do
      create(:user_session, user: @user)
      assert @user.recently_active?
    end

    test "is false if user only has an ancient session" do
      Timecop.freeze(@long_ago) do
        create(:user_session, user: @user)
      end
      refute @user.recently_active?
    end

    test "is true if user has recently starred a repo" do
      create :star, user: @user
      assert @user.recently_active?
    end

    test "is false if user only has an old starred repo" do
      Timecop.freeze(@long_ago) do
        create :star, user: @user
      end
      refute @user.recently_active?
    end

    test "is true if user recently watched a repo and auto-watch is disabled" do
      GitHub.newsies.get_and_update_settings(@user) { |s| s.auto_subscribe = false }
      @user.watch_repo create(:repository)

      assert @user.recently_active?
    end

    test "is false if user only has an old repo watch and auto-watch is disabled" do
      GitHub.newsies.get_and_update_settings(@user) { |s| s.auto_subscribe = false }
      # Timecop seems to have no power over this one...
      @user.watch_repo create(:repository)

      Newsies::ListSubscription.where(user_id: @user.id).update_all(created_at: @long_ago)

      refute @user.recently_active?
    end

    test "is false if user recently watched a repo and auto-watch is enabled" do
      GitHub.newsies.get_and_update_settings(@user) { |s| s.auto_subscribe = true }
      @user.watch_repo create(:repository)

      refute_predicate @user, :recently_active?
    end

    test "is true if user has a recent feed event" do
      only = [ProcessEventJob, UpdateEventFeedsJob]
      perform_enqueued_jobs(only: only) { create(:issue, :with_instrumentation, :wait_for_orchestration, user: @user) }
      assert @user.recently_active?
    end

    test "is false if user's newest feed event is too old" do
      Timecop.freeze(@long_ago) do
        create(:issue, user: @user)
      end
      refute @user.recently_active?
    end

    test "is true if the user has a recent audit log entry" do
      with_es_refresh do
        log action: "user.change_password", actor_id: @user.id
      end

      assert @user.recently_active?
    end

    test "is false if the user has only old audit log entries" do
      with_es_refresh do
        Timecop.freeze(@long_ago) do
          log action: "user.create", actor_id: @user.id
        end
      end

      refute @user.recently_active?
    end

    test "is false if the user has only failstate audit log entries" do
      with_es_refresh do
        log action: "user.failed_login", actor_id: @user.id
      end

      refute @user.recently_active?
    end

    test "is true if the user has recent login entries" do
      with_es_refresh do
        log action: "user.login", actor_id: @user.id
      end

      assert @user.recently_active?
    end

    test "is false if the user has no recent login entries" do
      with_es_refresh do
        Timecop.freeze(@long_ago) do
          log action: "user.login", actor_id: @user.id
        end
      end

      refute @user.recently_active?
    end

    test "is true if user has recent password resets" do
      with_es_refresh do
        log action: "user.reset_password", actor_id: @user.id
      end

      assert @user.recently_active?
    end

    test "is false if the user has no recent password resets" do
      with_es_refresh do
        Timecop.freeze(@long_ago) do
          log action: "user.reset_password", actor_id: @user.id
        end
      end

      refute @user.recently_active?
    end

    test "is true if user has recent email verifications" do
      with_es_refresh do
        log action: "user_email.confirm_verification", actor_id: @user.id
      end

      assert @user.recently_active?
    end

    test "is false if the user has no recent email verifications" do
      with_es_refresh do
        Timecop.freeze(@long_ago) do
          log action: "user_email.confirm_verification", actor_id: @user.id
        end
      end

      refute @user.recently_active?
    end

    test "is true if user has recent issue comments" do
      with_es_refresh do
        log action: "issue_comment.update", actor_id: @user.id
      end

      assert @user.recently_active?
    end

    test "is false if the user has no recent issue comments" do
      with_es_refresh do
        Timecop.freeze(@long_ago) do
          log action: "issue_comment.update", actor_id: @user.id
        end
      end

      refute @user.recently_active?
    end

    if GitHub.enterprise?
      test "is false if user has recently accessed a personal token" do
        create(:personal_token_oauth_access, user: @user, accessed_at: @recently)
        assert_predicate @user, :recently_active?
      end

      test "is true if user has not recently accessed a personal token" do
        create(:personal_token_oauth_access, user: @user, accessed_at: @long_ago)
        refute_predicate @user, :recently_active?
      end

      test "is false if user has recently accessed a public key" do
        create(:public_key, user: @user, accessed_at: @recently)
        assert_predicate @user, :recently_active?
      end

      test "is true if user has not recently accessed a public key" do
        create(:public_key, user: @user, accessed_at: @long_ago)
        refute_predicate @user, :recently_active?
      end
    end
  end

  context "#dormancy_status" do
    unless GitHub.enterprise?
      test "paid" do
        @user.update plan: "Micro"
        status = @user.dormancy_status
        assert status[:paid]
        refute status[:dormant]
        assert_includes status[:active_keys], :paid
      end
    end

    test "base user is dormant" do
      assert @user.dormancy_status[:dormant]
      assert_equal [], @user.dormancy_status[:active_keys]
    end

    test "build_dormancy_status result is memoized" do
      @user.expects(:build_dormancy_status).once.returns({})
      @user.dormancy_status
      @user.expects(:build_dormancy_status).never
      @user.dormancy_status
    end

    test "user was created recently" do
      user = nil
      Timecop.freeze(15.minutes.ago) do
        user = create(:user)
      end
      status = user.dormancy_status
      assert is_active_time?(status[:created_at])
      refute status[:dormant]
      assert_includes status[:active_keys], :created_at
    end

    test "2fa enabled" do
      @user.update two_factor_credential: create(:two_factor_credential)
      status = @user.dormancy_status
      assert status[:two_factor]
      refute status[:dormant]
      assert_includes status[:active_keys], :two_factor
    end

    test "has recent payment" do
      @user.stubs(:last_billing_transaction_time).returns(15.minutes.ago)
      status = @user.dormancy_status
      assert is_active_time?(status[:last_transaction])
      refute status[:dormant]
      assert_includes status[:active_keys], :last_transaction
    end

    test "owns a recently created repo" do
      create(:private_repository, owner: @user)
      status = @user.dormancy_status
      assert_equal 1, status[:repo_owner_count]
      assert status[:active_repo_owner]
      refute status[:dormant]
      assert_includes status[:active_keys], :active_repo_owner
      assert_includes status[:active_keys], :repo_owner_count
    end

    test "has an old fork with no recent activity" do
      Timecop.freeze(@long_ago) do
        original_owner = create(:user)
        forkable_repo = create(:repository, owner: original_owner)
        forked_repo, reason, errors = forkable_repo.fork(forker: @user)
      end

      status = @user.dormancy_status
      assert status[:dormant]
      assert_equal [], status[:active_keys]
    end

    test "has an old fork with recent push" do
      Timecop.freeze(@long_ago) do
        original_owner = create(:user)
        forkable_repo = create(:repository, owner: original_owner, from_example: :simple)

        @forked_repo, reason, errors = forkable_repo.fork(forker: @user)
        example_repo(:simple, @forked_repo)
        @new_pusher = create(:user)
        @forked_repo.add_member(@new_pusher)
      end
      assert @forked_repo.dormant?
      assert @user.dormant?

      @forked_repo.update(pushed_at: Time.now - 15.minutes)

      status = @user.reload.dormancy_status
      assert status[:active_repo_owner]
      refute status[:dormant]
      assert_includes status[:active_keys], :active_repo_owner
    end

    test "has recent dashboard event" do
      perform_enqueued_jobs(only: [ProcessEventJob, UpdateEventFeedsJob]) { repo = create :repository, :full_creation, owner: @user }
      status = @user.dormancy_status
      assert is_active_time?(status[:last_event])
      refute status[:dormant]
      assert_includes status[:active_keys], :last_event
    end

    test "member of a repo" do
      Timecop.freeze(@long_ago) do
        user2 = create(:user)
        repo = create(:private_repository, owner: user2)
        repo.add_member(@user)
      end
      status = @user.dormancy_status
      assert status[:repo_member]
      refute status[:dormant]
      assert_includes status[:active_keys], :repo_member
    end

    test "user has a public gist" do
      Timecop.freeze(@long_ago) do
        create(:gist, owner: @user)
      end
      status = @user.dormancy_status
      assert_equal 1, status[:gist_count]
      refute status[:dormant]
      assert_includes status[:active_keys], :gist_count
    end

    test "user has a secret gist" do
      Timecop.freeze(@long_ago) do
        create(:gist, owner: @user, public: false)
      end
      status = @user.dormancy_status
      assert_equal 1, status[:gist_count]
      refute status[:dormant]
      assert_includes status[:active_keys], :gist_count
    end

    test "has a personal access token" do
      Timecop.freeze(@long_ago) do
        create(:personal_token_oauth_access, user: @user)
      end
      status = @user.dormancy_status
      assert status[:oauth_accesses]
      refute status[:dormant]
      assert_includes status[:active_keys], :oauth_accesses
    end

    test "has a third party oauth_access" do
      Timecop.freeze(@long_ago) do
        github = make_trusted_oauth_apps_owner
        not_github = create(:organization, login: "not-github")
        third_party_app = create(:oauth_application, user: not_github)
        create(:oauth_access, user: @user, application: third_party_app)
      end
      status = @user.dormancy_status
      assert status[:oauth_accesses]
      refute status[:dormant]
      assert_includes status[:active_keys], :oauth_accesses
    end

    test "has a public key" do
      Timecop.freeze(@long_ago) do
        create(:public_key, user: @user)
      end
      status = @user.dormancy_status
      assert status[:public_keys]
      refute status[:dormant]
      assert_includes status[:active_keys], :public_keys
    end

    test "has an active package" do
      Timecop.freeze(@long_ago) do
        repo = create(:public_repository, owner: @user)
        package = repo.packages.create(name: "an-active-package", package_type: :rubygems)
      end
      status = @user.dormancy_status
      assert_equal 1, status[:public_packages_count]
      assert_equal 1, status[:repo_owner_count]
      refute status[:dormant]
      assert_includes status[:active_keys], :public_packages_count
      assert_includes status[:active_keys], :repo_owner_count
    end

    test "has starred a repo recently" do
      repo = nil
      Timecop.freeze(@long_ago) do
        repo = create(:repository)
      end
      @user.star(repo)
      status = @user.dormancy_status
      assert is_active_time?(status[:last_star])
      refute status[:dormant]
      assert_includes status[:active_keys], :last_star
    end

    test "watching a repo and auto-watch is disabled" do
      refute GitHub.newsies.settings(@user).auto_subscribe?
      Timecop.freeze(@long_ago) do
        @repo = create(:repository)
      end
      @user.watch_repo(@repo)
      status = @user.dormancy_status
      assert is_active_time?(status[:last_watch])
      refute status[:dormant]
      assert_includes status[:active_keys], :last_watch
    end

    test "has recent session" do
      create(:user_session, user: @user)
      status = @user.dormancy_status
      assert is_active_time?(status[:last_session])
      refute status[:dormant]
      assert_includes status[:active_keys], :last_session
    end

    test "has recently verified email" do
      @user.emails.create(state: "verified", email: "verified_email@github.com", verified_at: 15.minutes.ago)
      status = @user.dormancy_status
      assert is_active_time?(status[:last_email_verification])
      refute status[:dormant]
      assert_includes status[:active_keys], :last_email_verification
    end

    test "has recent issue comment" do
      create(:issue_comment, user: @user)
      status = @user.dormancy_status
      assert_equal 1, status[:all_comment_count]
      assert is_active_time?(status[:last_comment])
      refute status[:dormant]
      assert_includes status[:active_keys], :all_comment_count
      assert_includes status[:active_keys], :last_comment
    end

    test "has recent commit comment" do
      create(:commit_comment, user: @user)
      status = @user.dormancy_status
      assert_equal 1, status[:all_comment_count]
      assert is_active_time?(status[:last_comment])
      refute status[:dormant]
      assert_includes status[:active_keys], :last_comment
      assert_includes status[:active_keys], :all_comment_count
    end

    test "has old commit comment" do
      Timecop.freeze(@long_ago) do
        create(:commit_comment, user: @user)
      end
      status = @user.dormancy_status
      assert_equal 1, status[:all_comment_count]
      refute is_active_time?(status[:last_comment])
      refute status[:dormant]
      assert_includes status[:active_keys], :all_comment_count
    end

    test "has recent issue" do
      Timecop.freeze(@long_ago) do
        create(:issue, user: @user)
      end
      status = @user.dormancy_status
      assert_equal 1, status[:all_comment_count]
      refute is_active_time?(status[:last_comment])
      refute status[:dormant]
      assert_includes status[:active_keys], :all_comment_count
    end

    test "has old issue" do
      create(:issue, user: @user)
      status = @user.dormancy_status
      assert_equal 1, status[:all_comment_count]
      refute status[:dormant]
      assert_includes status[:active_keys], :all_comment_count
      assert_includes status[:active_keys], :last_comment
    end

    test "has recent login" do
      with_es_refresh do
        log action: "user.login", user_id: @user.id
      end
      status = @user.dormancy_status
      assert is_active_time?(status[:last_login])
      refute status[:dormant]
      assert_includes status[:active_keys], :last_login
    end

    test "has recent invite to organization" do
      with_es_refresh do
        other_user = create(:user)
        log action: "org.invite_member", user_id: @user.id, actor_id: other_user.id
      end
      status = @user.dormancy_status
      assert is_active_time?(status[:last_org_invite])
      refute status[:dormant]
      assert_includes status[:active_keys], :last_org_invite
    end

    test "has recently changed password" do
      with_es_refresh do
        log action: "user.change_password", user_id: @user.id
      end
      status = @user.dormancy_status
      assert is_active_time?(status[:last_password_reset])
      refute status[:dormant]
      assert_includes status[:active_keys], :last_password_reset
    end

    unless GitHub.enterprise?
      test "member of a recently active organization" do
        org = create(:organization, plan: "free")
        org.add_member(@user)
        status = @user.dormancy_status
        assert_equal 1, status[:active_org_membership_count]
        assert_equal 1, status[:ignored][:org_membership_count]
        refute status[:dormant]
        assert_includes status[:active_keys], :active_org_membership_count
      end

      test "member of an organization with no recent activity" do
        org = nil
        Timecop.freeze(@long_ago) do
          org = create(:organization, plan: "free")
          org.add_member(@user)
        end
        status = @user.dormancy_status
        assert_equal 0, status[:active_org_membership_count]
        assert_equal 1, status[:ignored][:org_membership_count]
        assert status[:dormant]
        assert_equal [], status[:active_keys]
      end
    end

  end

  context "#signup_timeframe" do
    test "is 'onboarding' when < 24 hours old" do
      @user.stubs(:created_at).returns(12.hours.ago)
      assert_equal "onboarding", @user.signup_timeframe
    end

    test "is 'recent' when < 1 month old" do
      @user.stubs(:created_at).returns(15.days.ago)
      assert_equal "recent", @user.signup_timeframe
    end

    test "is 'established' when > 1 month old" do
      @user.stubs(:created_at).returns(32.days.ago)
      assert_equal "established", @user.signup_timeframe
    end

    test "is 'unknown' for unsaved users" do
      user = build(:user)
      assert_equal "unknown", user.signup_timeframe
    end
  end
end
