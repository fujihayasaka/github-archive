# typed: true
# frozen_string_literal: true

require "test_helper"

class OAuthAccessTest < GitHub::TestCase
  include HydroTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @user = create(:user, login: "user")
    @other_user = create(:user, login: "other-user", plan: "medium")
    @staff = create(:staff_admin_user)

    @public_repo = create(:repository, :minimal, name: "public_repo", owner: @user)
    @other_public_repo = create(:repository, :minimal, name: "public_repo", owner: @other_user)
    @private_repo = create(:private_repository, :minimal, name: "private_repo", owner: @other_user)

    @org = create :organization, admin: @user
    @app = create :oauth_application, user: @user
    @other_app = create :oauth_application, user: @user

    @integration = create :integration, user_token_expiration_enabled: false

    @access = create :oauth_access, user: @user, application: @app, scopes: %w(user)
    @access_token = @access.reset_token
    @other_access = create :oauth_access, user: @user, application: @app, scopes: %w(user)

    @key = Sham.ssh_public_key
  end

  test "requires user" do
    access = build :oauth_access, user: nil, application: @app
    refute access.valid?
    assert access.errors[:user_id].any?
  end

  test "rejects an Organization as user" do
    access = build :oauth_access, user: @org, application: @app
    refute access.valid?
    assert access.errors[:user].any?
  end

  test "rejects a Bot as user" do
    bot = create(:integration).bot
    access = build :oauth_access, user: bot, application: @app
    refute access.valid?
    assert access.errors[:user].any?
  end

  test "rejects very long descriptions" do
    descr = "a" * 300
    personal_access = build(:personal_token_oauth_access, user: @user, description: descr)
    refute personal_access.valid?
    assert personal_access.errors[:note].any?
  end

  test "creates scim:enterprise scope" do
    personal_access = build(:personal_token_oauth_access, user: @user, scopes: %w(scim:enterprise))
    assert_predicate personal_access, :valid?
  end

  if GitHub.email_verification_enabled?
    test "rejects a user who must_verify_email?" do
      unverified = create(:user)
      unverified.stubs(:must_verify_email?).returns(true)
      access = build :oauth_access, user: unverified, application: @app
      refute access.valid?
      assert access.errors[:user].any?
    end

    test "allows unverified users for capable internal applications" do
      unverified = create(:user)
      unverified.stubs(:must_verify_email?).returns(true)

      app = create(:oauth_application)
      Apps::Privileged::Registry.configure(
        app_alias: :some_oauth_app,
        app: app,
        id: ->(*) { app.id },
        capabilities: {
          skip_oauth_user_eligibility_check: true
        }
      )

      access = create :oauth_access, user: unverified, application: app
      assert access.valid?
    end
  end

  context "for a Marketplace installation" do
    if GitHub.enterprise?
      test "does not enqueue MarketplaceOauthAppInstallJob in Enterprise" do
        assert_no_enqueued_jobs(only: MarketplaceOauthAppInstallJob) do
          create :oauth_access, user: @user, application: @app
        end
      end
    end

    unless GitHub.enterprise?
      test "enqueues MarketplaceOauthAppInstallJob" do
        assert_enqueued_jobs(1, only: MarketplaceOauthAppInstallJob) do
          create :oauth_access, user: @user, application: @app
        end
      end

      test "updates related subscription items" do
        listing = create(:marketplace_listing, listable: @app)
        listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
        plan_subscription = create(:billing_plan_subscription, user: @org)
        subscription_item = Billing::SubscriptionItem.create(plan_subscription: plan_subscription, subscribable: listing_plan)

        perform_enqueued_jobs(only: [MarketplaceOauthAppInstallJob]) do
          access = create :oauth_access, user: @user, application: @app
          assert access.valid?
          assert subscription_item.reload.installed_at.present?
        end
      end
    end
  end

  test "requires valid scopes" do
    access = build :oauth_access, user: @user, application: @app
    access.scopes = ["user", :booya]
    assert !access.valid?
    assert access.errors[:scopes].any?
  end

  test "requires application" do
    access = build :oauth_access, application: nil, user: @user
    assert !access.valid?
    assert access.errors[:application_id].any?
  end

  test "requires unique code in app" do
    access = build :oauth_access, user: @user,
      application: @app, code: @access.code
    assert !access.valid?
    assert access.errors[:code].any?
  end

  test "can clear invalid scopes" do
    access = build :oauth_access, user: @user, application: @app
    access.grant "abc,user"
    assert_equal %w(user), access.scopes
  end

  test "grant resets code and clears all token related values" do
    code, hashed_token, token_last_eight = @access.code, @access.hashed_token, @access.token_last_eight
    @access.grant "repo, user"
    assert_equal %w(repo user), @access.scopes
    refute_nil @access.code
    refute_equal code, @access.code
    assert_nil @access.hashed_token
    assert_nil @access.token_last_eight
  end

  # Once a token value is set on an access we intend to return the same token
  # related values on subsequent redemptions.
  test "redeem clears code and returns token related values if token is already set" do
    code, hashed_token, token_last_eight = @access.code, @access.hashed_token, @access.token_last_eight
    @access.redeem
    assert_nil @access.code
    refute_equal code, @access.code
    refute_nil @access.hashed_token
    refute_equal hashed_token, @access.hashed_token
    refute_nil @access.token_last_eight
    refute_equal token_last_eight, @access.token_last_eight
  end

  test "allows duplicate code in other app" do
    access = build :oauth_access, user: @user,
      application: @other_app, code: @access.code
    assert access.valid?
  end

  test "requires unique hashed_token" do
    access = build :oauth_access, user: @user,
      application: @app, hashed_token: @access.hashed_token
    assert !access.valid?
    assert access.errors[:hashed_token].any?
  end

  test "reset_with_expiry with an expires_at" do
    time = Time.now

    access = make_personal_access_token(@user, ["user"])

    new_token = access.reset_with_expiry(expires_at: time)
    access.save!
    access.reload

    assert_equal time.utc.to_s, access.expires_at.to_s
  end

  test "reset_without_expiration does not set an expiration" do
    time = DateTime.now

    access = make_personal_access_token(@user, ["user"])

    new_token = access.reset_without_expiry
    access.save!

    assert_nil access.expires_at
  end

  test "updates token_last_eight when token is reset" do
    access = build :oauth_access, user: @user, application: @app
    new_token = access.reset_token
    access.save!
    access.reload

    refute_nil access.hashed_token
    refute_nil access.token_last_eight
    assert_equal new_token.last(8), access.token_last_eight
    assert access.valid?
    assert access.errors[:token_last_eight].empty?
  end

  test "clears invalid scopes when token is reset" do
    access = build :oauth_access, user: @user, application: @app
    access.scopes = %w(admin:org foobar)
    new_token = access.reset_token
    assert_equal %w(admin:org), access.scopes
  end

  test "updates hashed_token when token is reset" do
    access = build :oauth_access, user: @user, application: @app
    new_token = access.reset_token
    access.save!
    access.reload

    refute_nil access.hashed_token
    assert_equal OauthAccess.hash_token(new_token), access.hashed_token
    assert access.valid?
    assert access.errors[:hashed_token].empty?
  end

  test "logs information when it encounters a database uniqueness constraint error" do
    access_one = create :oauth_access_with_token, user: @user, application: @app
    access = build :oauth_access, user: @user, application: @app

    expected_log = {
      "Body" => "OauthAccess Errors: Hashed token has already been taken",
      "gh.oauth_access.valid" => false
    }

    access.stubs(:hash_token).returns(access_one.hashed_token)

    assert_logged(**expected_log) do
      assert_raises(ActiveRecord::RecordInvalid) do
        access.reset_token
      end
    end
  end

  test "knows whether it is a personal access token" do
    refute @access.personal_access_token?

    personal_access = create(:personal_token_oauth_access, user: @user)
    assert personal_access.personal_access_token?
  end

  test "knows whether it is a personal access token that can be used for account recovery" do
    refute @access.personal_access_token_eligible_for_account_recovery?(Time.current)

    personal_access = create(:personal_token_oauth_access, user: @user, scopes: ["repo"], created_at: Time.current - 1.minute, expires_at_timestamp: Time.current + 1.minute)
    assert personal_access.personal_access_token_eligible_for_account_recovery?(Time.current)
  end

  test "exposes description errors as note errors" do
    personal_access = build(:personal_token_oauth_access, description: "", user: nil)

    refute personal_access.valid?
    assert personal_access.errors[:description].empty?
    assert personal_access.errors[:note].any?

    expected_errors = ["Note can't be blank", "User can't be blank"]
    assert_equal expected_errors, personal_access.errors.full_messages.sort
  end

  test "exposes description errors as note errors when submit unicode characters" do
    personal_access = build(:personal_token_oauth_access, description: "test 🚀", user: @user)

    refute personal_access.valid?
    assert personal_access.errors[:description].empty?
    assert personal_access.errors[:note].any?

    expected_error = ["Note doesn't accept 4-byte Unicode"]
    assert_equal expected_error, personal_access.errors.full_messages
  end

  test "does not allow duplicate note for personal access tokens" do
    access  = create(:personal_token_oauth_access, user: @user, description: "Note")
    another = build(:personal_token_oauth_access, user: @user, description: "Note")

    refute access.new_record?
    refute another.valid?
    assert another.errors[:note].any?
    assert another.errors[:description].empty?
  end

  test "description cannot include the PAT prefix (ghp_)" do
    access = build(:personal_token_oauth_access, user: @user, description: "ghp_foo")
    access.save
    refute access.valid?
    # description errors are exposed as :note
    assert_includes access.errors[:note], "can't include GitHub token prefix"

    # test it ignores leading whitespaces
    access = build(:personal_token_oauth_access, user: @user, description: "    ghp_foo")
    access.save
    refute access.valid?
    assert_includes access.errors[:note], "can't include GitHub token prefix"

    access = build(:personal_token_oauth_access, user: @user, description: "zomg.ghp_foo")
    access.save
    refute access.valid?
    assert_includes access.errors[:note], "can't include GitHub token prefix"
  end


  test "does not allow duplicate fingerprint when present" do
    access = create(:personal_token_oauth_access, user: @user, fingerprint: "Token1")
    another  = build(:personal_token_oauth_access, user: @user, fingerprint: "Token1")

    refute access.new_record?
    refute another.valid?
    assert another.errors[:fingerprint].any?
  end

  test "does allow duplicate note for personal access tokens if they have a unique fingerprint" do
    access = create(:personal_token_oauth_access, user: @user, fingerprint: "Token1")
    another  = create(:personal_token_oauth_access, user: @user, fingerprint: "Token2")

    refute access.new_record?
    refute another.new_record?
    assert another.errors[:description].empty?
    assert another.errors[:fingerprint].empty?
  end

  test "does allow duplicate fingerprint when blank" do
    access  = create(:personal_token_oauth_access, user: @user, fingerprint: nil)
    another = create(:personal_token_oauth_access, user: @user, fingerprint: nil)

    refute access.new_record?
    assert access.valid?
    assert_nil access.fingerprint
    assert access.errors[:fingerprint].empty?
    refute another.new_record?
    assert another.valid?
    assert_nil access.fingerprint
    assert another.errors[:fingerprint].empty?
  end

  test "accesses user" do
    assert_equal @user, @access.reload.user
  end

  test "accesses application" do
    assert_equal @app, @access.reload.application
    assert_equal @app, @access.safe_app
  end

  test "accesses OauthApplication directly" do
    assert_equal OauthApplication, @access.reload.application.class
    assert_equal @app, @access.oauth_application
  end

  test "accesses Integration directly" do
    access = create(:oauth_access, user: @user, application: @integration)

    assert_equal Integration, access.reload.application.class
    assert_equal @integration, access.integration
  end

  test "personal access token has app" do
    @access.application_id = OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
    assert_nil @access.application
    default = OauthApplication.default(@access.description, @access.note_url)
    assert_equal default.name, @access.safe_app.name
    assert_equal default.url, @access.safe_app.url
    assert_equal default.id, @access.application_id
  end

  test "personal access token has app with notes" do
    @access.application_id = OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
    @access.note = "abc"
    @access.note_url = "def"
    assert_nil @access.application
    assert_equal OauthApplication.default, @access.safe_app
    assert_equal @access.safe_app.id, @access.application_id
    assert_equal "abc", @access.safe_app.name
    assert_equal "def", @access.safe_app.url
  end

  test "personal access token has 0s for key, secret" do
    @access.application_id = OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
    key = OauthApplication::PERSONAL_TOKENS_CLIENT_ID
    assert_equal key, @access.safe_app.key
  end

  test "is valid" do
    assert @access.valid?
  end

  test "#reset_code resets the code" do
    old_code = @access.code
    @access.reset_code
    refute_equal old_code, @access.reload.code
  end

  test "has a code, hashed_code, and token_last_eight" do
    assert @access.code
    assert @access.token_last_eight
    assert_equal @access_token.last(8), @access.token_last_eight
    assert @access.hashed_token
    assert_equal OauthAccess.hash_token(@access_token), @access.hashed_token
    assert_equal @access, OauthAccess.find_by(code: @access.code)
    assert_equal @access, OauthAccess.with_active_token(@access_token)
    assert_equal @access, OauthAccess.find_by(hashed_token: @access.hashed_token)
  end

  test "oauth tokens match OauthAccess::TOKEN_PATTERN" do
    token = @access.reset_token

    assert_match /\Agho_/, token
    assert_match OauthAccess::TOKEN_PATTERN, token
  end

  test "user-to-server tokens match OauthAccess::TOKEN_PATTERN" do
    @integration.update(user_token_expiration: true)
    access = create :github_app_access, application: @integration

    token, _ = access.redeem

    assert_match /\Aghu_/, token
    assert_match OauthAccess::TOKEN_PATTERN, token
  end

  test "personal access tokens match OauthAccess::TOKEN_PATTERN" do
    pat = create(:personal_token_oauth_access, user: @user)
    token = pat.reset_token

    assert_match /\Aghp_/, token
    assert_match OauthAccess::TOKEN_PATTERN, token
  end

  test "tokens are generated with random characters" do
    token_value_1 = @access.reset_token
    token_value_2 = @access.reset_token

    assert_match /[a-zA-Z0-9]{36}\z/i, token_value_1
    assert_match /[a-zA-Z0-9]{36}\z/i, token_value_2
    refute_equal token_value_1, token_value_2
  end

  test "finds user by authorized token" do
    perform_enqueued_jobs(only: [OauthAccessBumpJob]) do
      Timecop.freeze do
        user = User.with_oauth_hashed_token(@access.hashed_token)
        user.oauth_access.reload
        assert_equal @user, user
        assert_equal @app.id, user.oauth_application_id
        assert_equal ["user"],  user.oauth_access.access_level
        assert_equal Time.now.to_i, user.oauth_access.accessed_at.to_i
        assert user.oauth_access?(:user)
      end
    end
  end

  test "doesn't find organization by authorized token" do
    @access.user = @org
    @access.save(validate: false)
    assert_equal @org, OauthAccess.with_active_token(@access_token).user
    assert_nil User.with_oauth_hashed_token(@access.hashed_token)
  end

  # https://github.com/github/github/issues/33480
  test "doesn't find access when not passed in as a String" do
    assert_equal @access, OauthAccess.with_active_token(@access_token)
    # Passing `token` in via a Hash, Array, or any other non-String object will
    # always return `nil`.
    assert_nil OauthAccess.with_active_token({ access_token: @access_token })
    assert_nil OauthAccess.with_active_token([@access_token])
  end

  test "with_active_oauth_token returns a user if token is not expired" do
    integration = create(:integration)

    access = integration.grant(@user)
    token, _refresh_token = access.redeem

    assert access.expires_at > Time.now

    result = OauthAccess.with_active_token(token)
    refute_nil result
  end

  test "with_active_oauth_token returns nil if token is expired" do
    integration = create(:integration)

    access = integration.grant(@user)
    token, _refresh_token = access.redeem

    access.update!(expires_at: 0)

    result = OauthAccess.with_active_token(token)
    assert_nil result
  end

  test "expired? returns true if expiration time is past" do
    integration = create(:integration)

    access = integration.grant(@user)
    # This is what acutally sets expired_at
    _token, _refresh_token = access.redeem

    access.update!(expires_at: 0)

    assert_predicate access, :expired?
  end

  test "expired? returns false if expiration time is in the future" do
    integration = create(:integration)

    access = integration.grant(@user)
    # This is what actually sets expired_at
    _token, _refresh_token = access.redeem

    refute_predicate access, :expired?
  end

  test "DEFAULT_INSTALLATION_TOKEN_EXPIRY is 8 hours" do
    assert_equal 8.hours, OauthAccess::DEFAULT_INSTALLATION_TOKEN_EXPIRY,
      "The default token expiry should be 8 hours, as agreed with AppSec. "\
      "See https://github.com/github/appsec-reviews/issues/447 for discussion"
  end

  test "staff user can get site_admin scope" do
    acc = build :oauth_access, user: @staff, application: @app
    acc.grant "site_admin,user"
    assert_equal %w(site_admin user), acc.scopes
  end

  test "normal user cannot get site_admin scope" do
    acc = build :oauth_access, user: @user, application: @app
    acc.grant "site_admin,user"
    assert_equal %w(user), acc.scopes
  end

  test "normalizes scopes" do
    [nil, "", " , , "].each do |empty|
      assert_equal [], OauthAccess.normalize_scopes(empty), empty.inspect
    end
  end

  test "normalize scopes with real data" do
    assert_equal %w[repo user], OauthAccess.normalize_scopes("repo,user")
    assert_equal ["repo"], OauthAccess.normalize_scopes("repo")
  end

  test "normalizes access levels" do
    assert_equal %w(repo user), OauthAccess.normalize_scopes("repo,user,user:email")
    assert_equal %w(user), OauthAccess.normalize_scopes("user,user:email")
    assert_equal %w(admin:org repo), OauthAccess.normalize_scopes("repo,read:org,admin:org,write:org")
  end

  test "determines if active scopes are the same as requested" do
    acc = build :oauth_access, user: @user, application: @app
    acc.grant "repo", "user,repo"
    refute acc.original_scopes_granted?
    acc.set_scopes("user,repo")
    assert acc.original_scopes_granted?
  end

  test "normalizes and removes duplicate scopes" do
    assert_equal %w[repo user], OauthAccess.normalize_scopes("user,repo,repo,user,repo:status")
  end

  test "big red button removes oauth access" do
    assert @staff.site_admin?
    @staff.oauth_accesses.destroy
    assert_equal 0, @staff.oauth_accesses.count
    staff_repo_access = create :oauth_access, user: @staff, application: @app, scopes: %w(repo public_repo)
    staff_site_admin_access = create :oauth_access, user: @staff, application: @app, scopes: %w(site_admin)
    assert_equal 2, @staff.oauth_accesses.count

    @staff.staff_revoke
    assert @staff.oauth_accesses.empty?
  end

  test "determines access_level based on given scopes" do
    acc = OauthAccess.new
    assert_equal [], acc.access_level!
    acc.scopes = %w(foo)
    assert_equal [], acc.access_level!
    acc.scopes = %w(user)
    assert_equal ["user"], acc.access_level!
    acc.scopes = %w(repo)
    assert_equal ["repo"], acc.access_level!
    acc.scopes = %w(user repo repo:status)
    assert_equal ["user", "repo", "repo:status"], acc.access_level!
  end

  test "adds scopes" do
    token = @access_token
    @access.change_scopes("repo")
    @access.reload
    assert_equal %w[repo user], @access.scopes
    assert_equal OauthAccess.hash_token(token), @access.hashed_token
  end

  test "adds scopes via list" do
    @access.change_scopes("delete_repo, repo:status")
    assert_equal ["delete_repo", "repo:status", "user"], @access.scopes
  end

  test "adds scopes via array" do
    @access.change_scopes(%w(delete_repo repo:status))
    assert_equal ["delete_repo", "repo:status", "user"], @access.scopes
  end

  test "replaces scopes via list" do
    @access.change_scopes("user:email, repo:status", "user")
    assert_equal ["repo:status", "user:email"], @access.scopes
  end

  test "replaces scopes via array" do
    @access.change_scopes(%w(user:email repo:status), "user")
    assert_equal ["repo:status", "user:email"], @access.scopes
  end

  test "#bump when oauth_access_update_async feature enabled enqueues job" do
    with_cache_enabled do
      Timecop.freeze(Time.zone.now) do
        oauth_access = create(:oauth_access, accessed_at: nil)
        assert_nil GitHub.cache.get("oauth_accesses:last_accessed:#{oauth_access.id}")

        oauth_access.bump

        assert_enqueued_jobs 1, only: OauthAccessBumpJob, queue: :oauth_access_bumps
        assert_nil oauth_access.reload.accessed_at
        assert_equal Time.zone.now, GitHub.cache.get("oauth_accesses:last_accessed:#{oauth_access.id}")
      end
    end
  end

  test "#bump! also bumps authorization with same time" do
    Timecop.freeze(Time.at(1542131343)) do
      perform_enqueued_jobs(only: [OauthAuthorizationBumpJob]) do
        with_cache_enabled do
          now = 4.days.ago
          oauth_authorization = create(:oauth_authorization, accessed_at: nil)
          oauth_access = create(:oauth_access, {
            accessed_at: nil,
            authorization: oauth_authorization,
            user: oauth_authorization.user,
            application: oauth_authorization.application,
          })

          oauth_access.bump!(now)

          assert_equal now.to_i, oauth_access.reload.accessed_at.to_i
          assert_equal now.to_i, oauth_authorization.reload.accessed_at.to_i
        end
      end
    end
  end

  context ".matches_pattern?" do
    test "returns true if matches an OAuth Access pattern" do
      token = SecureRandom.hex(20)

      assert OauthAccess.matches_pattern?(token)
    end

    test "returns true if matches the new OAuth Access patterns" do
      # Oauth access
      token_oauth = @access.reset_token

      # User to server
      @integration.update(user_token_expiration: true)
      access = create :github_app_access, application: @integration
      token_integration, _ = access.redeem

      # Personal access token
      pat = create(:personal_token_oauth_access)
      token_pat = pat.reset_token

      assert OauthAccess.matches_pattern?(token_pat)
      assert OauthAccess.matches_pattern?(token_integration)
      assert OauthAccess.matches_pattern?(token_oauth)
    end

    test "returns false if given token is refresh token" do
      @integration.update(user_token_expiration: true)
      access = create :github_app_access, application: @integration
      _token, refresh_token = access.redeem

      refute OauthAccess.matches_pattern?(refresh_token)
    end
  end

  context "number of accesses is limited" do
    test "when too many accesses are created for a given application and scope" do
      # Clear existing accesses since we want to test quantity limits.
      # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      perform_enqueued_jobs { @app.async_revoke_tokens(entry_point: :test_case) }
      # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

      assert_difference "OauthAccess.count", OauthAccess::MAXIMUM_ACCESSES_FOR_APP do
        OauthAccess::MAXIMUM_ACCESSES_FOR_APP.times do
          create(:oauth_access,
            user: @user,
            application: @app,
            scopes: %w(user),
          )
        end
      end

      assert_no_difference "OauthAccess.count" do
        create(:oauth_access,
          user: @user,
          application: @app,
          scopes: %w(user),
        )
      end
    end

    test "for each unique set of scopes" do
      # Clear existing accesses since we want to test quantity limits.
      # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      perform_enqueued_jobs { @app.async_revoke_tokens(entry_point: :test_case) }
      # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

      assert_difference "OauthAccess.count", OauthAccess::MAXIMUM_ACCESSES_FOR_APP do
        OauthAccess::MAXIMUM_ACCESSES_FOR_APP.times do
          create(:oauth_access,
            user: @user,
            application: @app,
            scopes: %w(user),
          )
        end
      end

      assert_difference "OauthAccess.count", OauthAccess::MAXIMUM_ACCESSES_FOR_APP do
        OauthAccess::MAXIMUM_ACCESSES_FOR_APP.times do
          create(:oauth_access,
            user: @user,
            application: @app,
            scopes: %w(user repo),
          )
        end
      end
    end

    test "and destroys the least recently used access when the limit is exceeded" do
      # Clear existing accesses since we want to test quantity limits.
      # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      perform_enqueued_jobs { @app.async_revoke_tokens(entry_point: :test_case) }
      # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

      accesses = []
      assert_difference "OauthAccess.count", OauthAccess::MAXIMUM_ACCESSES_FOR_APP do
        OauthAccess::MAXIMUM_ACCESSES_FOR_APP.times do |i|
          accesses << create(:oauth_access,
            user: @user,
            application: @app,
            scopes: %w(user),
            accessed_at: i.days.ago,
          )
        end
      end

      least_recently_accessed = accesses.min_by { |access| access.accessed_at }
      create(:oauth_access,
        user: @user,
        application: @app,
        scopes: %w(user),
      )
      assert_nil OauthAccess.find_by(id: least_recently_accessed.id)
    end

    test "and destroys the oldest unused access when the limit is exceeded" do
      # Clear existing accesses since we want to test quantity limits.
      # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      perform_enqueued_jobs { @app.async_revoke_tokens(entry_point: :test_case) }
      # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

      unused_accesses = []
      assert_difference "OauthAccess.count", OauthAccess::MAXIMUM_ACCESSES_FOR_APP do
        unused_accesss_count = OauthAccess::MAXIMUM_ACCESSES_FOR_APP / 2
        used_access_count = OauthAccess::MAXIMUM_ACCESSES_FOR_APP - unused_accesss_count
        unused_accesss_count.times do |i|
          unused_accesses << create(:oauth_access,
            user: @user,
            application: @app,
            scopes: %w(user),
            accessed_at: nil,
            created_at: i.days.ago,
          )
        end

        used_access_count.times do |i|
          create(:oauth_access,
            user: @user,
            application: @app,
            scopes: %w(user),
            accessed_at: i.days.ago,
          )
        end
      end

      oldest_unused = unused_accesses.min_by { |access| access.created_at }
      create :oauth_access, user: @user, application: @app, scopes: %w(user)
      assert_nil OauthAccess.find_by(id: oldest_unused.id)
    end

    test "and does not destroy accesses where there is also an installation" do
      integration = create(:integration, default_permissions: { "metadata" => :read })
      make_integration_installation(integration: integration, target: @user)

      access = create(:oauth_access, user: @user, application: integration)

      assert_difference "OauthAccess.count", OauthAccess::MAXIMUM_ACCESSES_FOR_APP do
        OauthAccess::MAXIMUM_ACCESSES_FOR_APP.times do
          _, error_response = integration.grant_scoped_access_from(access, @user)
          assert_nil error_response
        end
      end

      assert_difference "OauthAccess.count" do
        _, error_response = integration.grant_scoped_access_from(access, @user)
        assert_nil error_response
      end
    end
  end

  context "application specific access limit overrides are supported" do
    test "when an oauth application is allowlisted" do
      # Clear existing accesses since we want to test quantity limits.
      # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      perform_enqueued_jobs { @app.async_revoke_tokens(entry_point: :test_case) }
      # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

      access_limit_override = OauthAccess::MAXIMUM_ACCESSES_FOR_APP * 2
      GitHub.stubs(:oauth_access_limit_overrides_enabled?).returns(true)
      OauthAccess.stub_const(
        :MAXIMUM_ACCESSES_FOR_APP_OVERRIDES,
        { @app.id => access_limit_override },
      ) do
        assert_difference "OauthAccess.count", access_limit_override do
          access_limit_override.times do
            create(:oauth_access,
              user: @user,
              application: @app,
              scopes: %w(user),
            )
          end
        end

        assert_no_difference "OauthAccess.count" do
          create(:oauth_access,
            user: @user,
            application: @app,
            scopes: %w(user),
          )
        end
      end
    end

    test "when an integration is allowlisted" do
      # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      perform_enqueued_jobs { @integration.async_revoke_tokens }
      # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

      GitHub.stubs(:oauth_access_limit_overrides_enabled?).returns(true)
      access_limit_override = 3
      stubs = {
        MAXIMUM_ACCESSES_FOR_APP: 2,
        MAXIMUM_ACCESSES_FOR_APP_OVERRIDES: { @integration.id => access_limit_override },
      }
      OauthAccess.stub_consts(stubs) do
        assert_difference "@integration.accesses.count", access_limit_override do
          access_limit_override.times do
            @integration.grant(@user)
          end
        end

        assert_no_difference "@integration.accesses.count" do
          @integration.grant(@user)
        end
      end
    end
  end

  context "integration limits" do
    test "is the same as an Oauth App when an integration is not using refresh tokens" do
      # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      perform_enqueued_jobs { @integration.async_revoke_tokens }
      # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

      oauth_max = 2
      stubs = {
        MAXIMUM_ACCESSES_FOR_APP: oauth_max,
        MAXIMUM_ACCESSES_FOR_EXPIRING_APP: 5,
      }
      OauthAccess.stub_consts(stubs) do
        assert_difference "@integration.accesses.count", oauth_max do
          oauth_max.times do
            @integration.grant(@user)
          end
        end

        assert_no_difference "@integration.accesses.count" do
          @integration.grant(@user)
        end
      end
    end

    test "is elevated when an Integration is not using refresh tokens" do
      @integration.update!(user_token_expiration: true)
      # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      perform_enqueued_jobs { @integration.async_revoke_tokens }
      # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

      expiring_max = 5
      stubs = {
        MAXIMUM_ACCESSES_FOR_APP: 2,
        MAXIMUM_ACCESSES_FOR_EXPIRING_APP: expiring_max,
      }
      OauthAccess.stub_consts(stubs) do
        assert_difference "@integration.accesses.count", expiring_max do
          expiring_max.times do
            @integration.grant(@user)
          end
        end

        assert_no_difference "@integration.accesses.count" do
          @integration.grant(@user)
        end
      end
    end
  end

  context "#scopes_string" do
    test "returns a sorted, comma-separated list of scopes" do
      access = OauthAccess.new(scopes: %w(user:email repo))
      assert_equal "repo,user:email", access.scopes_string
    end

    test "returns an empty string for an access with no scopes" do
      access = OauthAccess.new(scopes: nil)
      assert_equal "", access.scopes_string
    end
  end

  context "updating an OauthAccess" do
    test "updates associated OauthAuthorization when scopes are changed" do
      oauth_access = T.let(nil, T.nilable(OauthAccess))
      oauth_authorization = T.let(nil, T.nilable(OauthAccess))

      Timecop.freeze(1.day.ago) do
        oauth_authorization = create :oauth_authorization
        oauth_access = create :oauth_access, \
          authorization: oauth_authorization,
          user: oauth_authorization.user,
          application: oauth_authorization.application
      end

      access = T.must(oauth_access)
      authorization = T.must(oauth_authorization)

      updated_at = authorization.updated_at

      access.change_scopes(%w[repo user])
      access.save!
      authorization.reload

      refute_equal updated_at, authorization.updated_at
    end

    test "updates associated OauthAuthorization when personal access token description is changed" do
      oauth_access = T.let(nil, T.nilable(OauthAccess))
      oauth_authorization = T.let(nil, T.nilable(OauthAccess))

      Timecop.freeze(1.day.ago) do
        oauth_authorization = create :oauth_authorization
        oauth_access = create :oauth_access, \
          authorization: oauth_authorization,
          user: oauth_authorization.user,
          application: oauth_authorization.application
      end

      access = T.must(oauth_access)
      authorization = T.must(oauth_authorization)

      updated_at = authorization.updated_at

      # required for `update_authorization` to trigger this condition
      access.stubs(:personal_access_token?).returns(true)

      access.description = "updated"
      access.save!
      authorization.reload

      assert_equal access.description, authorization.description
      refute_equal updated_at, authorization.updated_at
    end

    test "does not update associated OauthAuthorization if nothing is changed" do
      oauth_access = create(:oauth_access)

      oauth_authorization = oauth_access.authorization
      updated_at = oauth_authorization.updated_at

      oauth_access.save!
      oauth_authorization.reload

      assert_in_delta updated_at, oauth_authorization.updated_at
    end
  end

  context "deleting an OauthAccess" do
    test "does not delete user keys created by the OauthAccess" do
      user = @access.user
      public_key = user.public_keys.create_with_verification \
        key: @key, verifier: user, oauth_authorization: @access.authorization
      refute public_key.new_record?

      @access.destroy
      assert PublicKey.exists?(public_key.id)
    end

    test "does not delete user keys created by other OauthAccesses" do
      assert_equal @access.user, @other_access.user
      user = @other_access.user
      public_key = user.public_keys.create_with_verification \
        key: @key, verifier: user, oauth_authorization: @other_access.authorization

      @access.destroy
      assert PublicKey.exists?(public_key.id)
    end

    test "does not delete user keys created directly by the user" do
      user = @access.user
      public_key = user.public_keys.create_with_verification \
        key: @key, verifier: user

      @access.destroy
      assert PublicKey.exists?(public_key.id)
    end

    test "does not delete deploy keys created by the OauthAccess" do
      user = @access.user
      public_key = @public_repo.public_keys.create_with_verification \
        key: @key, verifier: user, oauth_authorization: @access.authorization

      @access.destroy
      assert PublicKey.exists?(public_key.id)
    end

    test "does not delete deploy keys created by other OauthAccesses" do
      assert_equal @access.user, @other_access.user
      user = @access.user
      public_key = user.public_keys.create_with_verification \
        key: @key, verifier: user, oauth_authorization: @access.authorization
      assert public_key.verify(user)

      @other_access.destroy
      assert PublicKey.exists?(public_key.id)
    end

    test "does not delete deploy keys created directly by the user" do
      user = @access.user
      public_key = user.public_keys.create_with_verification \
        key: @key, verifier: user

      @access.destroy
      assert PublicKey.exists?(public_key.id)
    end

    test "destroys associated installations" do
      integration = create(:integration, default_permissions: { "metadata" => :read })
      installation = make_scoped_integration_installation(
        parent: make_integration_installation(
          integration: integration, target: @user, permissions: { "metadata" => :read },
        ),
        repositories: [@public_repo],
      )

      access = create(:oauth_access, user: @user, application: integration)
      access.update!(installation: installation)
      assert_predicate installation, :persisted?
      access.destroy!
      refute ScopedIntegrationInstallation.exists?(installation.id)
    end

    test "destroys associated refresh_tokens" do
      integration = create(:integration)
      access = integration.grant(@user)
      access.redeem
      refresh_token = access.refresh_token
      assert_predicate refresh_token, :persisted?
      access.destroy!
      refute RefreshToken.exists?(refresh_token.id)
    end

    test "destroys associated device_authorization_grants" do
      integration = create(:integration)
      device_authorization_grant = create(
        :device_authorization_grant, application: integration,
      )
      access = integration.grant(@user)
      device_authorization_grant.update(oauth_access: access); access.reload
      assert_predicate device_authorization_grant, :persisted?
      access.destroy!
      refute DeviceAuthorizationGrant.exists?(device_authorization_grant.id)
    end

    test "throws an exception if an invalid destroy explanation is used" do
      assert_raises(ArgumentError) do
        @access.destroy_with_explanation(:foobar, entry_point: :test_case)
      end
    end
  end

  context "instrumentation" do
    test "instruments creation" do
      events = subscribe "oauth_access.create"

      access = create :oauth_access, user: @user, application: @app, scopes: %w(user)

      expected_payload = {
        oauth_access_id: access.id,
        scopes: ["user"],
        application_id: @app.id,
        application_name: @app.name,
        application_type: access.application_type,
        accessible_org_ids: [@org.id],
        user: @user.login,
        user_id: @user.id,
        token_last_eight: access.token_last_eight,
        hashed_token: access.hashed_token,
        token_id: access.id,
        token_scopes: "user",
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload

      unless GitHub.enterprise?
        expected_message = {
          request_context: nil,
          actor: Hydro::EntitySerializer.user(@user),
          database_id: access.id,
          app_type: :OAUTH_APPLICATION,
          oauth_application: Hydro::EntitySerializer.oauth_application(@app),
          integration: nil,
          scopes: access.scopes,
          accessible_organization_ids: [@org.id],
          expires_at_timestamp: nil,
          expires_at_preset: nil,
          expires_at_custom_date: nil,
        }
        assert_hydro_published(expected_message, schema: "github.v1.OauthAccess")
      end
    end

    test "instruments expiration on creation when available" do
      events = subscribe "oauth_access.create"

      access = create :oauth_access, :personal_token, user: @user, scopes: %w(user)

      expected_payload = {
        oauth_access_id: access.id,
        scopes: ["user"],
        application_id: access.application_id,
        application_name: access.description,
        application_type: access.application_type,
        accessible_org_ids: [@org.id],
        user: @user.login,
        user_id: @user.id,
        token_last_eight: access.token_last_eight,
        hashed_token: access.hashed_token,
        expires_at_preset: TokenExpirable::VALID_DEFAULT_EXPIRATIONS[access.default_expires_at].to_s,
        expires_at: nil,
        expires_at_custom_date: nil,
        token_id: access.id,
        token_scopes: "user",
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
    end

    test "instruments update when scope changes" do
      events = subscribe "oauth_access.update"

      @access.change_scopes("repo")

      expected_payload = {
        oauth_access_id: @access.id,
        scopes: %w[repo user],
        application_id: @app.id,
        application_name: @app.name,
        application_type: @access.application_type,
        accessible_org_ids: [@org.id],
        user: @user.login,
        user_id: @user.id,
        token_last_eight: @access.token_last_eight,
        hashed_token: @access.hashed_token,
        token_id: @access.id,
        token_scopes: "repo,user",
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments regenerate" do
      events = subscribe "oauth_access.regenerate"

      old_token_last_eight = @access.token_last_eight
      old_hashed_token = @access.hashed_token
      @access.reset_token

      expected_payload = {
        oauth_access_id: @access.id,
        scopes: ["user"],
        application_id: @app.id,
        application_name: @app.name,
        application_type: @access.application_type,
        accessible_org_ids: [@org.id],
        user: @user.login,
        user_id: @user.id,
        old_token_last_eight: old_token_last_eight,
        old_hashed_token: old_hashed_token,
        token_last_eight: @access.token_last_eight,
        hashed_token: @access.hashed_token,
        token_id: @access.id,
        token_scopes: "user",
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments expiration when available on regeneration" do
      access = create(:oauth_access, :personal_token, user: @user)
      access.reset_token

      events = subscribe "oauth_access.regenerate"

      old_token_last_eight = access.token_last_eight
      old_hashed_token = access.hashed_token

      date = 30.days.from_now
      access.reset_with_expiry(expires_at: date)

      expected_payload = {
        oauth_access_id: access.id,
        scopes: [],
        application_id: 0,
        application_name: access.description,
        application_type: access.application_type,
        accessible_org_ids: [@org.id],
        user: @user.login,
        user_id: @user.id,
        old_token_last_eight: old_token_last_eight,
        old_hashed_token: old_hashed_token,
        token_last_eight: access.token_last_eight,
        hashed_token: access.hashed_token,
        expires_at_preset: TokenExpirable::VALID_DEFAULT_EXPIRATIONS[@access.default_expires_at].to_s,
        expires_at: access.expires_at,
        expires_at_custom_date: nil,
        token_id: access.id,
        token_scopes: "",
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
    end

    test "instruments destroy without explanation" do
      events = subscribe "oauth_access.destroy"

      @access.destroy

      expected_payload = {
        oauth_access_id: @access.id,
        scopes: ["user"],
        application_id: @app.id,
        application_name: @app.name,
        application_type: @access.application_type,
        accessible_org_ids: [@org.id],
        user: @user.login,
        user_id: @user.id,
        token_last_eight: @access_token.last(8),
        hashed_token: OauthAccess.hash_token(@access_token),
        explanation: nil,
        token_id: @access.id,
        token_scopes: "user",
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload

      unless GitHub.enterprise?
        expected_message = {
          request_context: nil,
          actor: Hydro::EntitySerializer.user(@user),
          database_id: @access.id,
          app_type: :OAUTH_APPLICATION,
          oauth_application: Hydro::EntitySerializer.oauth_application(@app),
          integration: nil,
          scopes: @access.scopes,
          accessible_organization_ids: [@org.id],
          expires_at_timestamp: nil,
          expires_at_preset: nil,
          expires_at_custom_date: nil,
        }
        assert_hydro_published(expected_message, schema: "github.v1.OauthAccessDelete")
      end
    end

    if GitHub.guard_audit_log_staff_actor?
      test "hides staff actor when instrumenting a destroy from a staff actor" do
        events = subscribe "oauth_access.destroy"

        employee = create(:staff_admin_user)
        GitHub.context.push(actor_id: employee.id)
        @access.destroy

        expected_payload = {
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
          staff_actor: employee.login,
          staff_actor_id: employee.id,
          oauth_access_id: @access.id,
          scopes: ["user"],
          application_id: @app.id,
          application_name: @app.name,
          application_type: @access.application_type,
          accessible_org_ids: [@org.id],
          user: @user.login,
          user_id: @user.id,
          token_last_eight: @access_token.last(8),
          hashed_token: OauthAccess.hash_token(@access_token),
          explanation: nil,
          token_id: @access.id,
          token_scopes: "user",
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end

    test "increments stats on how a token was destroyed" do
      GitHub.dogstats.expects(:increment).at_least_once
      GitHub.dogstats.expects(:increment).with("account_security.oauth_access", has_entry(:tags, ["explanation:web-user", "action:destroy"]))
      @access.destroy_with_explanation(:web_user, entry_point: :test_case)
    end

    test "instruments destroy with specific explanation" do
      events = subscribe "oauth_access.destroy"

      @access.destroy_with_explanation(:stale, entry_point: :test_case)

      expected_payload = {
        oauth_access_id: @access.id,
        scopes: ["user"],
        application_id: @app.id,
        application_name: @app.name,
        application_type: @access.application_type,
        accessible_org_ids: [@org.id],
        user: @user.login,
        user_id: @user.id,
        hashed_token: @access.hashed_token,
        token_last_eight: @access.token_last_eight,
        explanation: :stale,
        token_id: @access.id,
        token_scopes: "user",
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments destroy when maximum accesses for an application is exceeded" do
      # Clear existing accesses since we want to test quantity limits.
      # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      perform_enqueued_jobs { @app.async_revoke_tokens(entry_point: :test_case) }
      # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

      events = subscribe "oauth_access.destroy"

      # Make an access that will be evicted (because it is the least recently
      # accessed) when OauthAccess::MAXIMUM_ACCESSES_FOR_APP is exceeded.
      access = create(:oauth_access,
        user: @user,
        application: @app,
        scopes: %w(user),
        accessed_at: 1.year.ago,
      )

      OauthAccess::MAXIMUM_ACCESSES_FOR_APP.times do
        create(:oauth_access,
          user: @user,
          application: @app,
          scopes: %w(user),
          accessed_at: 1.day.ago,
        )
      end

      expected_payload = {
        oauth_access_id: access.id,
        scopes: ["user"],
        application_id: access.application.id,
        application_name: access.application.name,
        application_type: access.application_type,
        accessible_org_ids: @user.organization_ids,
        user: @user.login,
        user_id: @user.id,
        hashed_token: access.hashed_token,
        token_last_eight: access.token_last_eight,
        explanation: :max_for_app,
        token_id: access.id,
        token_scopes: "user",
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    # https://github.com/github/ecosystem-apps/issues/3162
    test "instruments an orphan user-to-server token without raising" do
      access = @integration.grant(@user)

      @integration.delete

      access.reload
      assert_nil access.application

      events = subscribe "oauth_access.destroy"

      access.destroy

      app = Integration.new(id: access.application_id)

      expected_payload = {
        oauth_access_id: access.id,
        scopes: [],
        application_id: app.id,
        application_name: nil,
        application_type: "Integration",
        accessible_org_ids: [@org.id],
        user: @user.login,
        user_id: @user.id,
        token_last_eight: nil,
        hashed_token: nil,
        explanation: nil,
        token_id: access.id,
        token_scopes: "",
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload

      unless GitHub.enterprise?
        expected_message = {
          request_context: nil,
          actor: Hydro::EntitySerializer.user(@user),
          database_id: access.id,
          app_type: :INTEGRATION,
          oauth_application: nil,
          integration: Hydro::EntitySerializer.integration(app),
          scopes: access.scopes,
          accessible_organization_ids: [@org.id],
          expires_at_timestamp: nil,
          expires_at_preset: nil,
          expires_at_custom_date: nil,
        }
        assert_hydro_published(expected_message, schema: "github.v1.OauthAccessDelete")
      end
    end
  end

  context "#for_client_id" do
    test "returns accesses belonging to an Integration, for an integration specific client id" do
      integration = create(:integration)
      access_for_integration = create(:oauth_access, application: integration)

      assert_includes OauthAccess.for_client_id(integration.key), access_for_integration
    end

    test "returns accesses belonging to an OauthApplication, for an integration specific client id" do
      oauth_app = create :oauth_application
      access_for_oauth_app = create(:oauth_access, application: oauth_app)

      assert_includes OauthAccess.for_client_id(oauth_app.key), access_for_oauth_app
    end
  end

  context "#integration_application_type?" do
    test "returns true if access belongs to an Integration" do
      integration = create(:integration)
      access = build(:oauth_access, application: integration)
      assert access.integration_application_type?
    end

    test "returns false if access belongs to an OauthApplication" do
      oauth_app = create :oauth_application
      access = build(:oauth_access, application: oauth_app)
      refute access.integration_application_type?
    end

    test "returns false if access belongs to a Personal Access Token" do
      access = build(:personal_token_oauth_access)
      refute access.integration_application_type?
    end
  end

  context "#saml_enforceable?" do
    test "is true if the access is a personal access token" do
      access = create(:personal_token_oauth_access)
      assert_predicate access, :saml_enforceable?
    end

    test "is false if the internal app is not enforceable by SAML SSO" do
      integration = create_privileged_app_with_capabilities(capabilities: { saml_sso_required: false })
      access = create(:oauth_access, application: integration)

      refute_predicate access, :saml_enforceable?
    end

    test "is false for any other access" do
      legacy_access = T.let(OauthAccess.new, OauthAccess)

      Timecop.travel(Time.zone.parse("November 7th, 2019 09:00 PST")) do
        integration = create(:integration)
        legacy_access = create(:oauth_access, application: integration)
      end

      recent_access = create(:oauth_access)

      assert_predicate legacy_access, :saml_enforceable?
      assert_predicate recent_access, :saml_enforceable?
    end
  end

  context "organization credential authorizations" do
    test "are removed when their associated personal access token is deleted" do
      org = create(:organization)
      org_member = create(:user)
      org.add_member(org_member)
      pat = create(:personal_token_oauth_access, user: org_member)
      grant = Organization::CredentialAuthorization.grant(organization: org, credential: pat, actor: org_member)

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { pat.destroy }

      assert_nil Organization::CredentialAuthorization.authorization(organization: org, credential: pat)
    end

    test "are removed when their associated application access is deleted" do
      org = create(:organization)
      org_member = create(:user)
      org.add_member(org_member)
      access = create(:oauth_access, user: org_member)
      grant = Organization::CredentialAuthorization.grant(organization: org, credential: access, actor: org_member)

      assert_predicate access.reload, :is_application
      refute_predicate access, :personal_access_token?

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { access.destroy }

      refute Organization::CredentialAuthorization.find_by(id: grant.id)
    end

    test "are removed when their associated application is deleted" do
      org = create(:organization)
      org_member = create(:user)
      org.add_member(org_member)
      access = create(:oauth_access, user: org_member)
      grant = Organization::CredentialAuthorization.grant(organization: org, credential: access, actor: org_member)

      assert_predicate access.reload, :is_application
      refute_predicate access, :personal_access_token?
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { access.application.destroy }

      refute OauthAccess.find_by(id: access.id)
      refute Organization::CredentialAuthorization.find_by(id: grant.id)
    end

    test "are destroyed when the oauth access is modified" do
      org = create(:organization)
      org_member = create(:user)
      org.add_member(org_member)
      pat = create(:personal_token_oauth_access, user: org_member)
      grant = Organization::CredentialAuthorization.grant(organization: org, credential: pat, actor: org_member)

      # Simulate a user "regenerating" their PAT.
      # This action should require the user to re-authenticate via SAML SSO.
      pat.reset_token

      refute_includes Organization::CredentialAuthorization.by_organization(organization: org), grant
    end

    test "are destroyed when associated with multiple organizations" do
      org_one = create(:organization)
      org_two = create(:organization)
      org_member = create(:user)
      org_one.add_member(org_member)
      org_two.add_member(org_member)
      pat = create(:personal_token_oauth_access, user: org_member)
      grant_one = Organization::CredentialAuthorization.grant(organization: org_one, credential: pat, actor: org_member)
      grant_two = Organization::CredentialAuthorization.grant(organization: org_two, credential: pat, actor: org_member)

      # Simulate a user "regenerating" their PAT.
      # This action should require the user to re-authenticate via SAML SSO for
      # all organizations for which this PAT is allowlisted.
      pat.reset_token

      refute_includes Organization::CredentialAuthorization.by_organization(organization: org_one), grant_one
      refute_includes Organization::CredentialAuthorization.by_organization(organization: org_two), grant_two
    end

    test "are destroyed when scopes change" do
      org = create(:organization)
      org_member = create(:user)
      org.add_member(org_member)
      pat = create(:personal_token_oauth_access, user: org_member)
      grant = Organization::CredentialAuthorization.grant(organization: org, credential: pat, actor: org_member)

      # Simulate a user updating the scopes of their PAT.
      # This action should require the user to re-authenticate via SAML SSO.
      pat.scopes = OauthAccess.normalize_scopes("repo,user")
      assert pat.save, "should have updated scopes successfully"

      refute_includes Organization::CredentialAuthorization.by_organization(organization: org), grant
    end

    test "are not destroyed when they have been revoked by the organization" do
      org = create(:organization)
      org_member = create(:user)
      org.add_member(org_member)
      pat = create(:personal_token_oauth_access, user: org_member)
      grant = Organization::CredentialAuthorization.grant(organization: org, credential: pat, actor: org_member)

      # Simulate an org admin revoking the token.
      assert Organization::CredentialAuthorization.revoke(organization: org, credential: pat, actor: org.admins.first)

      # Simulate a user "regenerating" their PAT.
      pat.reset_token

      assert_includes Organization::CredentialAuthorization.by_organization(organization: org).revoked, grant
    end

    test "are not destroyed when the token is not a PAT" do
      org = create(:organization)
      org_member = create(:user)
      org.add_member(org_member)
      access = create(:oauth_access, user: org_member)
      grant = Organization::CredentialAuthorization.grant(organization: org, credential: access, actor: org_member)

      refute_predicate access, :personal_access_token?
      access.reset_token

      assert_includes Organization::CredentialAuthorization.by_organization(organization: org), grant
    end
  end

  context "expirations around a DST change" do
    test "can expire a key right before DST starts" do
      t = Time.at(1520762260)
      assert_equal "2018-03-11 01:57:40.000000000 PST -08:00", t.in_time_zone("US/Pacific").inspect, "sanity check"
      @access.expires_at = t
      @access.save!
      assert_equal t, OauthAccess.find(@access.id).expires_at, "expires_at after going through the DB"
    end

    test "can expire a key right after DST starts" do
      t = Time.at(1520765860)
      assert_equal "2018-03-11 03:57:40.000000000 PDT -07:00", t.in_time_zone("US/Pacific").inspect, "sanity check"
      @access.expires_at = t
      @access.save!
      assert_equal t, OauthAccess.find(@access.id).expires_at, "expires_at after going through the DB"
    end

    test "can expire a key right before DST ends" do
      t = Time.at(1509870000)
      assert_equal "2017-11-05 01:20:00.000000000 PDT -07:00", t.in_time_zone("US/Pacific").inspect, "sanity check"
      @access.expires_at = t
      @access.save!
      assert_equal t, OauthAccess.find(@access.id).expires_at, "expires_at after going through the DB"
    end

    test "can expire a key right after DST ends" do
      t = Time.at(1509873600)
      assert_equal "2017-11-05 01:20:00.000000000 PST -08:00", t.in_time_zone("US/Pacific").inspect, "sanity check"
      @access.expires_at = t
      @access.save!
      assert_equal t, OauthAccess.find(@access.id).expires_at, "expires_at after going through the DB"
    end
  end

  context "refreshing" do
    test "token_refreshable? is true for Integration types with feature flag enabled and opted in" do
      assert_equal "OauthApplication", @access.application_type
      refute_predicate @access, :token_refreshable?

      @integration.update!(user_token_expiration: false)
      access = create :github_app_access, application: @integration
      refute_predicate access, :token_refreshable?

      @integration.update!(user_token_expiration: true)
      access = create :github_app_access, application: @integration
      assert_predicate access, :token_refreshable?
    end

    test "token_refreshable? is false for Integration types with orphan tokens" do
      @integration.update!(user_token_expiration: true)

      access = create :github_app_access, application: @integration
      @integration.delete; access.reload

      refute_predicate access, :token_refreshable?
    end

    test "redeem generates a refresh token for GitHub Apps" do
      @access.redeem
      assert_nil @access.refresh_token

      @integration.update(user_token_expiration: true)
      access = create :github_app_access, application: @integration
      access.redeem
      refute_nil access.refresh_token
    end

    test "redeem returns a refresh token for GitHub Apps" do
      _token, refresh = @access.redeem
      assert_nil refresh

      @integration.update(user_token_expiration: true)
      access = create :github_app_access, application: @integration
      _token, refresh = access.redeem
      refute_nil refresh
    end

    test "redeem returns a token with extended expiry for codespaces" do
      expiry = 42.hours
      integration = create_privileged_app_with_capabilities(properties: { oauth_access_expiry: expiry })
      access = create :oauth_access, application: integration

      Timecop.freeze do
        _token, _refresh = access.redeem(extended_expiry: :true)
        assert_equal access.expires_at.to_i, expiry.from_now.to_i
      end
    end

    test "redeem returns a refresh token with shortened expiry for codespaces" do
      expiry = 12.hours
      integration = create_privileged_app_with_capabilities(properties: { refresh_token_expiry: expiry })
      access = create :oauth_access, application: integration

      Timecop.freeze do
        _token, _refresh = access.redeem(extended_expiry: :true)
        assert_equal access.refresh_token.expires_at.to_i, expiry.from_now.to_i
      end
    end

    test "redeem returns a token with the default expiry when an invalid application asks for extended expiry" do
      @integration.update(user_token_expiration: true)
      access = create :oauth_access, application: @integration

      Timecop.freeze do
        _token, _refresh = access.redeem(extended_expiry: :true)
        assert_equal access.expires_at.to_i, OauthAccess::DEFAULT_INSTALLATION_TOKEN_EXPIRY.from_now.to_i
      end
    end
  end

  context "#installation" do
    test "can be a ScopedIntegrationInstallation" do
      integration = create(:integration, default_permissions: { "metadata" => :read })

      installation = make_scoped_integration_installation(
        parent: make_integration_installation(integration: integration, target: @user, permissions: { "metadata" => :read }),
        repositories: [@public_repo],
      )

      access = create(:oauth_access, user: @user, application: integration)
      access.update(installation: installation)

      assert_predicate access, :valid?
      assert_kind_of ScopedIntegrationInstallation, access.installation
    end

    test "can be a SiteScopedIntegrationInstallation" do
      integration = create_unlimited_global_integration
      GitHub.flipper[:disabled_global_apps].disable(integration)

      result = SiteScopedIntegrationInstallation::Creator.perform(integration, @public_repo.owner, repositories: [@public_repo])
      assert_predicate result, :success?

      access = create(:oauth_access, user: @user, application: integration)
      access.update(installation: result.installation)

      assert_predicate access, :valid?
      assert_kind_of SiteScopedIntegrationInstallation, access.installation
    end

    test "cannot be an IntegrationInstallation" do
      installation = make_integration_installation(target: @user)

      access = create(:oauth_access, user: @user, application: installation.integration)
      access.update(installation: installation)

      refute_predicate access, :valid?
    end

    test "can only be set on Integration application types" do
      installation = make_scoped_integration_installation(
        parent: make_integration_installation(target: @user, permissions: { "metadata" => :read }),
        repositories: [@public_repo],
      )

      access = create(:oauth_access)
      access.update(installation: installation)

      refute_predicate access, :valid?
      assert_includes access.errors[:installation], "cannot be set for an OauthApplication"
    end

    test "must belong to the integration" do
      installation = make_scoped_integration_installation(
        parent: make_integration_installation(target: @user, permissions: { "metadata" => :read }),
        repositories: [@public_repo],
      )

      access = create(:oauth_access, user: @user, application: create(:integration))
      access.update(installation: installation)

      refute_predicate access, :valid?
      assert_includes access.errors[:installation], "installation does not belong to the Integration"
    end

    test "is destroyed when the access is destroyed" do
      parent = make_integration_installation(target: @user, permissions: { "metadata" => :read })
      integration = parent.integration

      access = integration.grant(@user)

      access, error = integration.grant_scoped_access_from(access, @user, permissions: parent.permissions, resources: { repository_ids: [@public_repo.id] }, entry_point: :test_case)
      assert_nil error

      assert_predicate access, :valid?
      assert_kind_of ScopedIntegrationInstallation, access.installation

      access.destroy

      assert_nil ScopedIntegrationInstallation.find_by(id: access.installation_id)
    end
  end

  context "for_tokens" do
    test "returns accesses grouped by raw token values" do
      access1 = create(:oauth_access, user: @user, scopes: %w(user))
      token1 = access1.reset_token
      access2 = create(:oauth_access, user: @user, scopes: %w(user))
      token2 = access2.reset_token
      access3 = create(:oauth_access, user: @user, scopes: %w(user))
      token3 = access3.reset_token

      tokens = OauthAccess.for_tokens([token1, token2, token3])
      assert_equal 3, tokens.size
      tokens.each do |_token, access|
        assert_predicate access.association(:user), :loaded?
      end

      assert_equal access1, tokens[token1]
      assert_equal access2, tokens[token2]
      assert_equal access3, tokens[token3]
    end

    test "returns accesses grouped by raw token values when we provide enough results to force multiple pages" do
      OauthAccess.stub_const(:TOKEN_BATCH_SIZE, 1) do
        access1 = create(:oauth_access, user: @user, scopes: %w(user))
        token1 = access1.reset_token
        access2 = create(:oauth_access, user: @user, scopes: %w(user))
        token2 = access2.reset_token
        access3 = create(:oauth_access, user: @user, scopes: %w(user))
        token3 = access3.reset_token

        tokens = OauthAccess.for_tokens([token1, token2, token3])
        assert_equal 3, tokens.size
        tokens.each do |_token, access|
          assert_predicate access.association(:user), :loaded?
        end

        assert_equal access1, tokens[token1]
        assert_equal access2, tokens[token2]
        assert_equal access3, tokens[token3]
      end
    end
  end

  context "last_issued_at" do
    test "is set when the hashed_token is set" do
      # Genereate a new token
      access = create(:oauth_access)
      access.set_random_token_pair
      access.save!

      assert_predicate access.last_issued_at, :present?
    end

    test "is updated when the hashed_token is updated" do
      # Genereate a new token
      access = create(:oauth_access)
      access.set_random_token_pair
      access.save!

      assert_predicate access.last_issued_at, :present?

      prev_last_issued_at = access.last_issued_at

      # Update the token
      access.reset_with_expiry(expires_at: Time.now)
      access.save!

      assert_predicate access.last_issued_at, :present?
      assert prev_last_issued_at < access.last_issued_at
    end
  end

  test ".third_party scope only returns accesses unrelated to GitHub-owned Apps" do
    github = make_trusted_oauth_apps_owner
    github_owned_app = create(:oauth_application, user: github)
    github_related_access = create(:oauth_access, application: github_owned_app)

    not_github = create(:organization, login: "not-github")
    third_party_app = create(:oauth_application, user: not_github)
    third_party_access = create(:oauth_access, application: third_party_app)

    accesses = OauthAccess.third_party
    assert_includes accesses, third_party_access
    refute_includes accesses, github_related_access
  end

  test ".github_owned scope only returns accesses related to GitHub-owned Apps" do
    github = make_trusted_oauth_apps_owner
    github_owned_app = create(:oauth_application, user: github)
    github_related_access = create(:oauth_access, application: github_owned_app)

    not_github = create(:organization, login: "not-github")
    third_party_app = create(:oauth_application, user: not_github)
    third_party_access = create(:oauth_access, application: third_party_app)

    accesses = OauthAccess.github_owned
    refute_includes accesses, third_party_access
    assert_includes accesses, github_related_access
  end
end
