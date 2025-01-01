# typed: false
# frozen_string_literal: true

require "test_helper"

class UserTest < GitHub::TestCase
  include HydroTestHelpers
  include HydroMessageJobTestHelpers
  include AuthenticationHelpers
  extend EncryptedColumnTestHelper

  self.these_tests_are_order_dependent_and_yearn_to_be_random

  fixtures do
    @business = nil
    @owner = create(:user, login: "owner", email: "owner@example.com", plan: "medium")

    @staffer = create(:staff_admin_user, login: "staffer", plan: "medium", email: "staffer@example.com")
    @free_user = create(:user, login: "free-user", email: "free-user@example.com")
    @paid_user = create(:user, login: "paid-user", email: "paid-user@example.com", plan: "medium")
    @grit = create(:repository, name: "grit", owner: @free_user, from_example: :pull_request_source)
    @ambition = create(:private_repository, name: "ambition", owner: @staffer)
    @facebox  = create(:repository, name: "facebox", owner: @staffer)
    @github   = create(:repository, name: "github", owner: @staffer)

    @paid_org = create(:organization, admin: @staffer, plan: GitHub::Plan.non_free_org_plans.first.name)
    @paid_org_team = create(:team, organization: @paid_org)
    @domain = create(:verifiable_domain, domain: "sombra.example.com", owner: @paid_org, verified: true)
    @other_domain = create(:verifiable_domain, domain: "mercy.example.com", owner: @paid_org, verified: true)
    @approved_domain = create(:verifiable_domain, domain: "salsa.example.com", owner: @paid_org, approved: true)

    oauth_app = make_oauth_app(@paid_user)
    @oauth_token = make_oauth(@free_user, [:repo], oauth_app).reset_token


    @issue = create(:issue, repository: @grit, user: @free_user, body: "hi")
    @issue2 = create(:issue, repository: @grit, user: @free_user, body: "##{@issue.number}")
  end

  setup do
    @old_suspended_users_visible = GitHub.suspended_users_visible?
    GitHub.suspended_users_visible = false
    GitHub.preview_features_enabled = true
    Failbot.reports.clear
    GitHub.cache.allow = /\Arate_limit:/
    GitHub.cache.clear
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  teardown do
    GitHub.suspended_users_visible = @old_suspended_users_visible
  end

  def create_user(options = {})
    User.create({
      login: "user-#{SecureRandom.hex(12)}",
      email: Faker::Internet.email,
      password: GitHub.default_password,
    }.merge(options))
  end

  test_encrypted_column(:user, :weak_password_check_result)

  test "should create user" do
    assert_difference "User.count" do
      user = create(:user)
      assert !user.new_record?, "#{user.errors.full_messages.to_sentence}"
      assert email = user.primary_user_email
      assert_equal email.to_s, user.email
    end
  end

  test "created user should accept Terms of Service" do
    user = create(:user)
    user.accept_tos
    user.valid?

    tos_acceptance = TosAcceptance.where(user_id: user.id).first
    assert_equal tos_acceptance.user_id, user.id
    assert_equal tos_acceptance.sha, TosAcceptance.current_sha
  end

  test "it validates pinned_api_version" do
    GitHub.stubs(:api_versions).returns(["2020-01-01"])
    user = build(:user, pinned_api_version: "bad")
    refute user.valid?
    assert_equal "Pinned api version is invalid", user.errors.full_messages.to_sentence
    user.pinned_api_version = "2020-01-01"
    assert user.valid?
  end

  test "should require login" do
    assert_no_difference "User.count" do
      u = create_user(login: nil)
      assert u.errors[:login].any?
    end
  end

  test "requires an email" do
    user = User.new
    user.valid?
    assert user.errors[:email].any?
  end

  test "doesn't require an email if using external auth" do
    GitHub.auth.stubs(:external?).returns(true)
    user = create_user email: nil
    assert user.valid?
    refute user.errors[:email].any?
  end

  test "login can be single alphanumeric" do
    u = create_user(login: "r")
    assert_valid u
  end

  test "login can start with a number" do
    u = create_user(login: "3n")
    assert_valid u
  end

  test "new login can't have an underscore" do
    assert_no_difference "User.count" do
      u = create_user(login: "hey_there")
      assert u.errors[:login].any?
    end
  end

  test "already-existing underscore login can stay" do
    u = create_user(login: "sneakyuser")
    assert_valid u
    u.update_column(:login, "sneaky_user")
    u.update_column(:display_login, "sneaky_user")
    u.reload

    assert_equal "sneaky_user", u.login

    u.update(last_ip: "8.8.8.8")
    assert_valid u
  end

  test "can't change login to include an underscore" do
    u = create_user(login: "sometestuser")
    assert_valid u

    u.login = "some_test_user"
    assert !u.valid?
    assert u.errors[:login].any?
  end

  test "new login can't end in a hyphen" do
    assert_no_difference "User.count" do
      u = create_user(login: "heynow-")
      assert u.errors[:login].any?
    end
  end

  test "existing users with ending hyphen logins can stay" do
    u = create_user(login: "legacyuser")
    assert_valid u
    u.update_column(:login, "legacyuser-")
    u.update_column(:display_login, "legacyuser-")
    u.reload

    assert_equal "legacyuser-", u.login

    u.update(last_ip: "8.8.8.8")
    assert_valid u
  end

  test "can't change login to end with a hyphen" do
    u = create_user(login: "sometestuser")
    assert_valid u

    u.login = "sometestuser-"
    assert !u.valid?
    assert u.errors[:login].any?
  end

  test "existing users with Unicode logins can stay" do
    u = create_user(login: "Khaos")
    assert_valid u
    u.update_column(:login, "\u212Ahaos")
    u.update_column(:display_login, "\u212Ahaos")
    u.reload

    assert_equal "\u212Ahaos", u.login

    u.update(last_ip: "8.8.8.8")
    assert_valid u
  end

  test "can't change login to include Unicode that downcases to ASCII" do
    u = create_user(login: "Khaos")
    assert_valid u

    u.login = "\u212Ahaos"
    assert !u.valid?
    assert u.errors[:login].any?
  end

  test "should deny multiline logins" do
    dhh = create_user login: "\r\ndhh"
    assert !dhh.valid?
  end

  test "login validation errors have a nice message" do
    u = build(:user, login: "#{@free_user} ")
    refute_predicate u, :valid?
    assert_equal "Username may only contain alphanumeric characters or single hyphens, and " \
                 "cannot begin or end with a hyphen. Username #{@free_user} is not available.",
                 u.login_error_message
  end

  test "should require a unique username" do
    assert_no_difference "User.count" do
      u = create_user(login: "paid-user")
      assert u.errors[:login].any?
    end
  end

  test "removes user from discussion and discussion comment on user deletion" do
    @free_user.emails.first.verify!
    discussion = create(:discussion, user: @free_user)
    comment = create(:discussion_comment, user: @free_user)

    assert @free_user.destroy

    assert_nil discussion.reload.user
    assert_nil comment.reload.user
  end

  test "removes account screening profile on user deletion" do
    user = create(:user)
    upp = create(:account_screening_profile, owner: user)

    user.destroy

    assert user.destroyed?
  end

  test "removes user metadata on user deletion" do
    user = create(:user)
    metadata = create(:user_metadata, user: user)

    user.destroy

    assert metadata.destroyed?
  end

  test "destroys issue type record when org is destroyed", feature_disabled: :hydro_issue_types_deletion_on_user_destroyed_kill_switch do
    owner = create(:organization)
    owner_id = owner.id
    queue = HydroIssueTypesDeletionOnUserDestroyedJob.queue_name
    schema = "github.v1.UserDestroy"
    message = {
      user: UserEntitySerializer.serialize(owner),
    }

    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
      assert_difference("IssueType.count", -3) do
        owner.destroy!
        perform_hydro_message_job(message, schema: schema, queue: queue)
      end
    end

    assert_raises ActiveRecord::RecordNotFound do
      User.find(owner_id)
    end
    assert_nil IssueType.find_by(owner_id: owner_id)
  end

  test "updates search indexes on user rename" do
    owner = create(:organization)
    repo = create(:repository, owner: owner)
    create(:issue, repository: repo)

    Search.expects(:add_to_search_index).with("user", owner.id).at_least_once
    Search.expects(:add_to_search_index).with("repository", repo.id).once
    Search.expects(:add_to_search_index).with("bulk_issues", repo.id, "purge" => true).once

    owner.rename!("new-name")
  end

  test "#verified_for_repo_actions? is false" do
    User.all.each do |user|
      refute_predicate user, :verified_for_repo_actions?
    end
  end

  test "standardize_login tests with and without suffix" do
    assert_equal "monalisa", User.standardize_login("monalisa@github.com")
    assert_equal "mona-lisa", User.standardize_login("mona_lisa@github.com")
    assert_equal "mona-lisa", User.standardize_login("mona.lisa@github.com")
    assert_equal "monalisa_bus", User.standardize_login("monalisa@github.com", suffix: "bus")
    assert_equal "mona-lisa_bus", User.standardize_login("mona.lisa@github.com", suffix: "bus")
    assert_equal "mona-lisa_bus", User.standardize_login("mona_lisa@github.com", suffix: "bus")

    # Sample logins for AAD guest users
    assert_equal "monalisa-gmail-com-EXT-onmicrosoft-com", User.standardize_login("monalisa_gmail.com#EXT#@aadsyncfabricprodpreview.onmicrosoft.com")
    assert_equal  "monalisa-gmail-com-EXT-onmicrosoft-com_bus", User.standardize_login("monalisa_gmail.com#EXT#@aadsyncfabricprodpreview.onmicrosoft.com", suffix: "bus")
  end


  if GitHub.enterprise?
    test "indicates it's hubot, only if it's persisted" do
      user = build :user, login: "hubot"
      refute user.rate_limit_exempt_user?

      user.save!
      refute user.rate_limit_exempt_user?
    end
  else
    test "indicates it's hubot, only if it's persisted" do
      user = build :user, login: "hubot"
      refute user.rate_limit_exempt_user?

      user.save!
      assert user.rate_limit_exempt_user?
    end

    context "#thehub_url" do
      test "returns nil for a non-staff user" do
        user = create(:user)

        assert_nil user.thehub_url
      end

      test "returns a proper URL for a staff user" do
        staff = create(:staff_admin_user)

        assert_equal "https://thehub.github.com/org?login=#{staff.login}", staff.thehub_url
      end
    end
  end

  context "#global_health_files_repository and #async_global_health_files_repository" do
    test "returns nil for orgs without .github repo" do
      assert_nil @paid_org.global_health_files_repository
      assert_nil @paid_org.async_global_health_files_repository.sync,
        "expected async method to be in agreement with sync method"
    end

    test "returns the health repo for an org" do
      repo = create(:repository, owner: @paid_org, name: Repository::GLOBAL_HEALTH_FILES_NAME)

      assert_equal repo, @paid_org.global_health_files_repository
      assert_equal repo, @paid_org.async_global_health_files_repository.sync,
        "expected async method to be in agreement with sync method"
    end

    test "returns nil for an inactive health repo" do
      create(:repository, owner: @paid_org, name: Repository::GLOBAL_HEALTH_FILES_NAME, active: false)

      assert_nil @paid_org.global_health_files_repository
      assert_nil @paid_org.async_global_health_files_repository.sync,
        "expected async method to be in agreement with sync method"
    end

    test "returns nil for orgs with private .github repo" do
      create(:private_repository, owner: @paid_org, name: Repository::GLOBAL_HEALTH_FILES_NAME)

      assert_nil @paid_org.global_health_files_repository
      assert_nil @paid_org.async_global_health_files_repository.sync,
        "expected async method to be in agreement with sync method"
    end

    if GitHub.enterprise?
      test "returns nil on GHES when repo is internal" do
        enterprise_org = create(:enterprise_linked_organization)
        create(:internal_repository, owner: enterprise_org, name: Repository::GLOBAL_HEALTH_FILES_NAME)

        assert_nil enterprise_org.global_health_files_repository
        assert_nil enterprise_org.async_global_health_files_repository.sync,
          "expected async method to be in agreement with sync method"
      end
    else
      test "returns nil for an enterprise-linked org on GitHub.com when repo is internal" do
        enterprise_org = create(:enterprise_linked_organization)
        create(:internal_repository, owner: enterprise_org, name: Repository::GLOBAL_HEALTH_FILES_NAME)

        assert_nil enterprise_org.global_health_files_repository
        assert_nil enterprise_org.async_global_health_files_repository.sync,
          "expected async method to be in agreement with sync method"
      end
    end
  end

  context "#unpublish_private_pages" do
    test "will depublish private repo pages if the user is trade restricted", skip_enterprise: true do
      GitHub.flipper[:pages_soft_deletion].disable
      user = create(:user)
      repo = create(:private_repository, owner: user)
      create(:page, repository: repo)
      user.trade_controls_restriction.full!

      assert repo.page
      assert repo.private?

      user.reload.unpublish_private_pages

      refute repo.reload.page
    end

  end

  test "should require a unique email" do
    assert_no_difference "User.count" do
      u = create_user email: "paid-user@example.com"

      assert u.errors[:emails].any?
      assert u.errors[:email].any?
      assert_includes u.errors.where(:email, :taken).first.message, "is already taken"
      assert_empty u.errors.where(:email, :sanctioned_email)
    end
  end

  test "should require non-sanctioned email" do
    assert_no_difference "User.count" do
      u = create_user email: "paid-user@example.gov.ir"
      assert u.errors[:emails].any?
      assert_includes u.errors.where(:email, :sanctioned_email).first.message, "may be for an entity restricted under U.S. trade controls"
    end
  end


  test "should require non-disposable email" do
    GitHub.stubs(prevent_disposable_email_verification?: true) # Make sure test also works for enterprise
    assert_no_difference "User.count" do
      u = create_user email: "paid-user@mailinator.com"
      assert u.errors[:emails].any?
      assert_equal u.errors.where(:email, :disposable_email).first.message, "domain could not be verified"
    end
  end

  context "safe_profile_name" do
    test "is the user's profile name when present" do
      user         = create(:user, login: "login-name")
      user.profile = create(:profile, name: "Profile Name")
      user.save

      assert_equal "Profile Name", user.safe_profile_name
    end

    test "is the user's login when their profile name is blank" do
      user = create(:user, login: "login-name")
      assert_equal "login-name", user.safe_profile_name
    end
  end

  context "has_pro_plan_badge?" do
    test "returns true if the user is on a pro plan and has opted into the badge" do
      user = create(:user, plan: "pro")
      user.profile_settings.pro_badge_enabled = true

      assert_predicate user, :has_pro_plan_badge?
    end

    test "returns false if the user is on a pro plan and has opted out of the badge" do
      user = create(:user, plan: "pro")
      user.profile_settings.pro_badge_enabled = false

      refute_predicate user, :has_pro_plan_badge?
    end

    test "returns false if the user is not on a pro plan but somehow is still opted into the badge" do
      user = create(:user)
      user.profile_settings.pro_badge_enabled = true

      refute_predicate user, :has_pro_plan_badge?
    end

    test "returns false if the user is an employee but otherwise would have the badge", skip_enterprise: true do
      user = create(:staff_admin_user, plan: "pro")
      user.profile_settings.pro_badge_enabled = true

      refute_predicate user, :has_pro_plan_badge?
    end
  end

  context "show_staff_badge_to?" do
    test "should return true if the user is GitHub.staff_user_login" do
      user = User.new(login: GitHub.staff_user_login)
      viewer = nil

      assert user.show_staff_badge_to?(viewer)
    end

    test "should return false if the user's metadata `is_staff` attribute is false" do
      user = create(:verified_user)
      create(:user_metadata, user: user, is_staff: false)
      viewer = nil

      refute user.show_staff_badge_to?(viewer)
    end

    context "viewer is an employee" do
      test "returns true if the user is an employee", skip_enterprise: true do
        user = create(:staff_admin_user)
        viewer = @staffer

        refute user.profile_display_staff_badge # show to employees regardless
        assert user.show_staff_badge_to?(viewer)
      end

      test "returns false if the user is not an employee" do
        user = create(:user)
        viewer = @staffer

        user.profile_display_staff_badge = true # even if their settings somehow say it should be shown
        user.save!

        refute user.show_staff_badge_to?(viewer)
      end
    end

    context "viewer is not an employee" do
      test "returns true if the user is an employee who wants the badge shown", skip_enterprise: true do
        user = @staffer
        viewer = @free_user

        user.profile_display_staff_badge = true
        user.save!

        assert user.show_staff_badge_to?(viewer)
      end

      test "returns false if the user is an employee but does not want their badge shown" do
        user = @staffer
        viewer = @free_user

        refute user.show_staff_badge_to?(viewer)
      end

      test "returns false if the user is not an employee" do
        user = @paid_user
        viewer = @free_user

        user.profile_display_staff_badge = true # even if their settings somehow say it should be shown
        user.save!

        refute user.show_staff_badge_to?(viewer)
      end
    end
  end

  context "recently_created" do
    test "should be true for default (no) arg and recent user" do
      user = create(:user, created_at: 12.hours.ago)
      assert user.recently_created?
    end

    test "should be false for very short arg and recent user" do
      user = create(:user, created_at: 12.hours.ago)
      refute user.recently_created? 3.minutes.ago
    end

    test "should be true for longer arg and recent user" do
      user = create(:user, created_at: 12.hours.ago)
      assert user.recently_created? 3.days.ago
    end
  end

  test "can own repositories" do
    user = create(:user)
    assert_predicate user, :can_own_repositories?
  end

  test "git author name is profile name if defined, otherwise login" do
    user = create(:user)
    user.update!(profile_name: "Awesome Sauce")
    assert_equal user.profile_name, user.git_author_name

    user.update!(profile_name: "")
    assert_equal user.login, user.git_author_name
  end

  test "git author name strips angle brackets" do
    user = create(:user)
    user.update!(profile_name: "Awe>some Sa<uce")
    assert_equal "Awesome Sauce", user.git_author_name
  end

  test "git author name falls back to login if profile name is empty after angle bracket stripping" do
    user = create :user, login: "elvinpresley"
    user.update!(profile_name: "<><><>")
    assert_equal "elvinpresley", user.git_author_name
  end

  test "should require email" do
    assert_no_difference "User.count" do
      u = create_user(email: nil)
      assert u.errors[:email].any?
    end
  end

  test "profile name allows high unicode" do
    user = create(:user)
    user.profile_name = "Ms. #{GRIN_EMOJI} Grin"
    assert_predicate user, :valid?
  end

  test "strips null byte from profile name" do
    user = create(:user)
    user.profile_name = "smol\u0000bean"
    user.save

    assert_equal "smolbean", user.reload.profile_name
  end

  test "allows emoji in profile bio" do
    user = create(:user)
    user.profile_bio = "So fun! #{GRIN_EMOJI}"
    assert user.valid?
    assert user.save
    assert_equal "So fun! #{GRIN_EMOJI}", user.reload.profile_bio
  end

  test "profile_pronouns sets, modifies and un-sets pronouns" do
    user = create(:user)
    assert_nil user.profile_pronouns
    user.profile_pronouns = "they/them"
    user.save!
    assert_equal "they/them", user.profile_pronouns
    user.profile_pronouns = "ze, hir"
    user.save!
    assert_equal "ze, hir", user.profile_pronouns
    user.profile_pronouns = nil
    user.save!
    assert_nil user.profile_pronouns
  end

  test "profile_social_accounts sets, modifies and un-sets social accounts" do
    user = create(:user)
    assert_nil user.profile_social_accounts

    twitter_account = create(:social_account_twitter)
    linkedin_account = create(:social_account_linkedin)
    mastodon_account = create(:social_account_mastodon)
    livejournal_account = create(:social_account, url: "https://monalisa.livejournal.com")

    user.profile_social_accounts = [twitter_account, linkedin_account]
    user.save!

    assert_equal [twitter_account, linkedin_account], user.profile_social_accounts

    user.profile_social_accounts = [livejournal_account, twitter_account, mastodon_account]
    user.save!

    assert_equal [livejournal_account, twitter_account, mastodon_account], user.profile_social_accounts

    user.profile_social_accounts = []
    user.save!

    assert_empty user.profile_social_accounts
  end

  test "limits user's profile bio to 48 characters" do
    user = create(:user)
    user.profile_pronouns = "a" * 49
    refute user.valid?
    assert_equal "is too long (maximum is 48 characters)",
                 user.errors[:profile_pronouns].first
  end

  test "user accepts latest version of ToS on profile update" do
    user = create(:user)

    Timecop.travel(2.seconds.ago) do
      user.accept_tos
    end

    tos_acceptance = TosAcceptance.where(user_id: user.id)

    user.profile_bio = "So fun! #{GRIN_EMOJI}"
    assert user.valid?
    assert user.save

    assert tos_acceptance.last[:created_at].to_i < tos_acceptance.last[:updated_at].to_i, "updated_at should have changed"
  end

  test "profile bio is utf-8" do
    user = create(:user)
    user.profile_bio = "So fun! #{GRIN_EMOJI}"
    assert user.valid?
    assert user.save
    assert_equal Encoding::UTF_8, user.reload.profile_bio.encoding
  end

  test "renders profile bio as HTML" do
    user = create(:user)
    user.profile_bio = "renders :rocket: as HTML"
    user.save!

    result_html = user.profile_bio_html
    assert_equal result_html, user.async_profile_bio_html.sync

    assert_includes result_html, "🚀"
  end

  test "limits user's profile bio to 160 characters" do
    user = create(:user)
    user.profile_bio = "a" * 161
    refute user.valid?
    assert_equal "is too long (maximum is 160 characters)",
                 user.errors[:profile_bio].first
  end

  test "renders company as HTML" do
    user = create(:user)
    user.profile_company = "@github"
    user.save!

    result_html = user.profile_company_html
    assert_equal result_html, user.async_profile_company_html.sync

    result = Nokogiri::HTML.parse(result_html)
    assert_equal "https://github.com/github", result.at_css("a")["href"]
  end

  test "gravatar_email must be unicode 3" do
    funny_character = [0x1F514].pack("U")
    funny_address   = "#{funny_character}blah@example.com"

    user = create_user(gravatar_email: funny_address)

    assert !user.valid?
    assert_includes user.errors[:gravatar_email], "doesn't accept 4-byte Unicode"
  end

  test "does not allow silent truncation of profile fields" do
    fields = %w[profile_name profile_email profile_blog profile_company
                profile_location]
    user = create(:user)
    profile = user.build_profile
    fields.each do |field|
      user.send(:"#{field}=", "a" * 256)
      refute user.valid?,
          "#{field} that is >255 characters long should not be valid"
      assert_equal "is too long (maximum is 255 characters)",
                   user.errors[field].first
    end
  end

  test "should add to search index on create" do
    now = Time.now
    timestamp = Timestamp.from_time(now)

    Timecop.freeze(now) do
      user = create_user
      guid = AddToSearchIndexJob.guid("user", user.id)
      assert_enqueued_with job: AddToSearchIndexJob, queue: "index_high", args: ["user", user.id, { "submitted_at" => timestamp, "guid" => guid }]
    end
  end

  test "should not add bot users to search index" do
    assert_enqueued_jobs 0, only: AddToSearchIndexJob, queue: :index_high do
      Bot.create(login: "super-ci")
    end
  end

  test "should add ghost user to the search index" do
    User.ghost.destroy
    ReservedLogin.untombstone!(GitHub.ghost_user_login)
    now = Time.now
    timestamp = Timestamp.from_time(now)

    Timecop.freeze(now) do
      ghost = create_user(login: GitHub.ghost_user_login)
      guid = AddToSearchIndexJob.guid("user", ghost.id)

      if GitHub.enterprise?
        assert_enqueued_jobs 0, only: AddToSearchIndexJob, queue: :index_high
      else
        assert_enqueued_with job: AddToSearchIndexJob, queue: "index_high", args: ["user", ghost.id, { "submitted_at" => timestamp, "guid" => guid }]
      end
    end
  end

  test "shouldnt allow periods" do
    chris = create_user login: "chris.wanstrath"
    assert !chris.valid?
  end

  test "can be staff" do
    assert @staffer.site_admin?
  end

  test "can't be staff without 2fa" do
    GitHub.require_two_factor_for_site_admin = true
    assert_equal false, @staffer.site_admin?
    GitHub.require_two_factor_for_site_admin = false
  end

  test "can masquerade as a non-staffer" do
    @staffer.site_admin = false
    assert !@staffer.site_admin?
  end

  test "can receive notifications" do
    assert User.new.newsies_enabled?
  end

  test "flipper_id is user id" do
    assert_equal "User:#{@staffer.id}", @staffer.flipper_id
  end

  test "knows how much disk space they are using" do
    example_repo :defunkt_ambition, @ambition
    example_repo :defunkt_facebox, @facebox
    @staffer.repositories.each(&:update_disk_usage)

    assert @staffer.disk_usage > 500,
      "disk usage #{@staffer.disk_usage} expected to be > 500"
  end

  context "requires_transfer_requests_from?" do
    test "a user requires transfer requests if the user is not self" do
      other = create(:user)
      assert @paid_user.requires_transfer_requests_from?(other)
    end

    test "a user does not require transfer requests if the user is self" do
      refute @paid_user.requires_transfer_requests_from?(@paid_user)
    end
  end

  context "hide_from_user?" do
    test "doesn't hide suspended users when 'suspended users are visible' feature flag is enabled" do
      GitHub.suspended_users_visible = true
      refute create(:suspended_user).hide_from_user?(nil)
    end

    test "hides suspended user from other regular users" do
      viewer = create(:user)
      assert create(:suspended_user).hide_from_user?(viewer)
    end

    test "hides suspended user from other nil (anonymous) user" do
      assert create(:suspended_user).hide_from_user?(nil)
    end

    test "doesn't hide suspended user from staff user" do
      refute create(:suspended_user).hide_from_user?(@staffer)
    end

    test "doesn't hide suspended user from themselves" do
      suspended_user = create(:suspended_user)
      refute suspended_user.hide_from_user?(suspended_user)
    end
  end

  test "creates two-factor credential" do
    make_two_factor_credential(@staffer)
    assert @staffer.two_factor_credential
  end

  if GitHub.two_factor_sms_enabled?
    test "two-factor authentication url" do
      make_two_factor_credential(@staffer)
      url = Addressable::URI.parse GitHub::TwoFactorAuthentication.provisioning_url_for_authenticator_app(@staffer.totp_app_registration&.encrypted_otp_secret, @staffer.login)
      assert_equal "otpauth", url.scheme
      assert_equal "totp", url.host
      assert_equal "/GitHub:github.com%2F#{@staffer.login}", url.path
      assert_equal GitHub::TwoFactorAuthentication.mashed_secret(@staffer.totp_app_registration.encrypted_otp_secret), url.query_values["secret"]
      assert_equal "GitHub", url.query_values["issuer"]
    end
  end

  test "event_context returns correct payload" do
    context = @staffer.event_context
    assert_equal @staffer.login, context[:user]
    assert_equal @staffer.id, context[:user_id]

    context = @staffer.event_context(prefix: :actor)
    assert_equal @staffer.login, context[:actor]
    assert_equal @staffer.id, context[:actor_id]
  end

  test "instruments user creation" do
    events = subscribe "user.create"

    user = create_user(login: "dewski")
    expected_payload = {
      user: user.login,
      user_id: user.id,
      actor: user.login,
      actor_id: user.id,
      email: user.email,
      plan: user.plan.name,
      solved_interactive_captcha: false,
    }

    assert event = events.pop, "an event was expected"
    assert_equal "user.create", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments user signup" do
    events = []
    GlobalInstrumenter.subscribe("user.signup") do |name, _, _, _, payload|
      events << { name: name, payload: payload }
    end

    user = create_user(login: "dewski", elected_to_receive_marketing_email: true)
    expected_payload = {
      actor: user,
      signup_email: user.emails.first,
      elected_to_receive_marketing_email: true,
    }

    assert global_event = events.pop, "a global event was expected"
    assert_equal "user.signup", global_event[:name]
    assert_equal expected_payload, global_event[:payload]
  end

  test "instruments resetting password" do
    events = subscribe "user.forgot_password"

    expected_payload = {
      user: @staffer.login,
      user_id: @staffer.id,
      email: @staffer.email,
      forced_reset: false,
    }

    email = @staffer.email
    reset = PasswordReset.create user: @staffer, email: email
    @staffer.forgot_password reset

    assert event = events.pop, "event expected"
    assert_equal expected_payload, event.payload
  end

  test "instruments forced password resets" do
    events = subscribe "user.forgot_password"

    expected_payload = {
      user: @staffer.login,
      user_id: @staffer.id,
      email: @staffer.email,
      forced_reset: true,
    }

    email = @staffer.email
    reset = PasswordReset.create user: @staffer, email: email, forced_weak_password_reset: true
    @staffer.forgot_password reset

    assert event = events.pop, "event expected"
    assert_equal expected_payload, event.payload
  end

  if GitHub.enterprise?
    test "instruments user deletion" do
      events = subscribe "user.delete"
      expected_payload = {
        user: @free_user.login,
        user_id: @free_user.id,
        email: @free_user.email,
        plan: "enterprise",
      }

      @free_user.destroy

      assert event = events.pop, "an event was expected"
      assert_equal "user.delete", event.name
      assert_equal expected_payload, event.payload
    end
  else
    test "instruments user deletion" do
      events = subscribe "user.delete"

      expected_payload = {
        user: @free_user.login,
        user_id: @free_user.id,
        email: @free_user.email,
        plan: "free",
      }

      @free_user.destroy

      assert event = events.pop, "an event was expected"
      assert_equal "user.delete", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "#find_or_create_profile" do
    test "returns existing profile" do
      expected = create(:profile, user: @free_user)
      actual = assert_no_difference(-> { Profile.count }) do
        @free_user.find_or_create_profile
      end
      assert_equal expected, actual
    end

    test "creates new profile when user does not yet have one" do
      profile = assert_difference(-> { Profile.count }) do
        @free_user.find_or_create_profile
      end
      refute_nil profile
      assert_equal profile, @free_user.profile
    end
  end

  test "instruments async_delete" do
    events = subscribe "user.async_delete"
    user = create(:user)
    user.async_destroy

    assert event = events.pop, "a user.async_delete event was expected"
    assert_equal "user.async_delete", event.name
  end

  test "skips instrumentation if #instrument_async_delete? is false" do
    events = subscribe "user.async_delete"

    user = create(:user)
    user.stubs(:instrument_async_delete?).returns(false)

    user.async_destroy

    refute event = events.pop, "a user.async_delete event was not expected"
  end

  test "verifies deleted_by is set without tenant suffix in multi-tenant env", skip_enterprise: true do
    business1 = create :business, business_type: :enterprise_managed, shortcode: "fab"
    business2 = create :business, business_type: :enterprise_managed, shortcode: "con"
    refute_equal(business1, business2)

    on_multi_tenant_enterprise do
      GitHub::CurrentTenant.set(business1)
      actor = create :emu, login: "ddotm", business: business1
      user1 = create :emu, login: "mtodd", business: business1
      GitHub::CurrentTenant.remove

      # not worried about the permitted check for this test
      user1.async_destroy(actor, skip_permitted_check: true)
      assert_equal "ddotm", user1.deleted_by

      GitHub::CurrentTenant.set(business2)
      user2 = create :emu, login: "mtodd", business: business2
      GitHub::CurrentTenant.remove

      # not worried about the permitted check for this test
      user2.async_destroy(actor, skip_permitted_check: true)
      assert_equal "ddotm", user2.deleted_by
    end
  end

  context "user settings dependency" do
    test "test default values are built for user settings" do
      user = create(:user)

      refute user.use_fixed_width_font?
      refute user.paste_url_link_as_plain_text?
    end

  end

  context "#remove_email" do
    test "instruments remove_email" do
      events = subscribe "user.remove_email"
      primary = @free_user.primary_user_email

      expected_payload = {
        email: primary.email,
        actor: @free_user.login,
        note: primary.email,
      }

      @free_user.add_email "another_email@extra.com"
      @free_user.remove_email(primary)

      new_primary = @free_user.primary_user_email

      expected_hydro_payload = {
        user: Hydro::EntitySerializer.user(@free_user),
        actor: Hydro::EntitySerializer.user(@free_user),
        primary_email: Hydro::EntitySerializer.user_email(new_primary),
        removed_email: Hydro::EntitySerializer.user_email(primary),
      }

      assert event = events.pop, "a user.remove_email event was expected"
      assert_equal "user.remove_email", event.name
      assert_equal event.payload.merge(expected_payload), event.payload

      assert_hydro_published(
        expected_hydro_payload,
        schema: "github.v1.UserRemoveEmail",
      )
      assert_hydro_messages(count: 1, schema: "github.v1.UserRemoveEmail")
    end

    test "succeeds if sponsors listing is not using email for contact email" do
      sponsorable = create(:verified_user)
      listing = create(:sponsors_listing, sponsorable: sponsorable)
      user_email = create(:verified_user_email, user: sponsorable)
      refute_equal user_email, listing.contact_email

      assert sponsorable.remove_email(user_email)
    end

    test "fails if draft sponsors listing is using email for contact email" do
      sponsorable = create(:verified_user)
      user_email = create(:verified_user_email, user: sponsorable)
      listing = create(:sponsors_listing, sponsorable: sponsorable,
        contact_email: user_email)
      assert_equal user_email, listing.contact_email

      refute sponsorable.remove_email(user_email)
      errors = sponsorable.errors.full_messages.to_sentence
      assert_match /change the email in your GitHub Sponsors settings/, errors
    end

    test "fails if waitlisted sponsors listing is using email for contact email" do
      sponsorable = create(:user)
      user_email = create(:verified_user_email, user: sponsorable)
      listing = create(:sponsors_listing, :waitlisted, sponsorable: sponsorable,
        contact_email: user_email)
      assert_equal user_email, listing.contact_email

      refute sponsorable.remove_email(user_email)
      errors = sponsorable.errors.full_messages.to_sentence
      assert_match /change the email for your GitHub Sponsors waitlist application/, errors
    end
  end

  test "upgrading a password's cost" do
    old_cost = GitHub.argon2_time_cost
    GitHub.stubs(:argon2_time_cost).returns(old_cost + 1)

    assert_match /t=#{old_cost}/, @staffer.password_hash
    assert_match /m=#{1 << GitHub.argon2_memory_cost}/, @staffer.password_hash
    @staffer.authenticated_by_password?(GitHub.default_password)

    assert_match /t=#{GitHub.argon2_time_cost}/, @staffer.password_hash
    assert_match /m=#{1 << GitHub.argon2_memory_cost}/, @staffer.password_hash
  end

  test "find by login or email with valid login" do
    assert_equal @staffer, User.find_by_login_or_email("staffer")
  end

  test "find by login or email with valid email" do
    assert_equal @staffer, User.find_by_login_or_email("staffer@example.com")
  end

  test "find by login with invalid login" do
    assert_nil User.find_by_login_or_email("missing_user")
    assert_nil User.find_by_login("%81%b8JAT")
    assert_nil User.find_by_login("\x81\xB8JAT")
  end

  test "find by login or email with valid email for first admin owner of multitenant enterprise" do
    on_multi_tenant_enterprise do
      emu_business = create(:business, :enterprise_managed, :without_enterprise_managed_user_owner)
      GitHub::CurrentTenant.set(emu_business)
      emu_business.create_and_add_first_emu_owner(email: "monalisa@github.com", actor: @user)
      first_admin_owner = User.find_by_login(emu_business.shortcode + "_admin")

      # verify looking up by login
      assert_equal first_admin_owner, User.find_by_login_or_email(emu_business.shortcode + "_admin")
      # verify looking up by the _known_ email address of the first admin owner
      assert_equal first_admin_owner, User.find_by_login_or_email("monalisa@github.com")
      # double check you can also look up by the "internal" email if you wanted to as a first admin owner
      assert_includes first_admin_owner.email, emu_business.shortcode
      assert_equal first_admin_owner, User.find_by_login_or_email(first_admin_owner.email)
    end
  end

  test "find by login or email with nil" do
    assert_nil User.find_by_login_or_email(nil)
  end

  test "find by login with 4 byte unicode" do
    assert_nil User.find_by_login("🇳🇱")
  end

  test "find by login with different data types" do
    assert_nil User.find_by_login(["foo"])
  end

  context ".reify" do
    test "returns the user if passed a user" do
      assert_equal @staffer, User.reify(@staffer)
    end

    test "finds a user by their login" do
      assert_equal @staffer, User.reify("staffer")
    end

    test "finds a user by their email" do
      assert_equal @staffer, User.reify("staffer@example.com")
    end

    test "returns nil if user doesn't exists" do
      assert_nil User.reify("nonexistent")
      assert_nil User.reify("nonexistent@example.com")
    end

    test "returns nil if passed nil" do
      assert_nil User.reify(nil)
    end
  end

  context "saving login metadata" do
    test "logs last ip" do
      @free_user.save_login_metadata(ip: "1.2.3.4")
      assert_equal "1.2.3.4", @free_user.last_ip
    end
  end

  context "instrument_login" do
    class FakeLog # rubocop:disable GitHub/ContextConstantDef
      attr_accessor :key, :data
      def log(audit_key, audit_data)
        @key = audit_key
        @data = audit_data
      end
    end

    test "creates audit log entry" do
      events = subscribe "user.login"
      expected_payload = {
        user: @free_user.login,
        user_id: @free_user.id,
        actor_ip: "127.0.0.1",
        actor: @free_user.login,
        actor_id: @free_user.id,
        two_factor: @free_user.two_factor_authentication_enabled?,
        user_session_id: "1",
        request_host: "github.com",
      }

      @free_user.instrument_login(actor_ip: "127.0.0.1", user_session_id: "1", request_host: "github.com")

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "instrument verifies user" do
    test "raises when :user is not a user" do
      GitHub.expects(:single_business_environment?).returns(false)
      Failbot.expects(:report).once.with do |error, context|
        assert_equal Instrumentation::Model::IdentifierError, error.class
        assert_equal "user.login", context[:action]
      end
      assert_raises(Instrumentation::Model::IdentifierError) do
        @free_user.instrument(:login, { user: @github })
      end
    end

    test "raises when :user id doesn't match :user_id" do
      GitHub.expects(:single_business_environment?).returns(false)
      Failbot.expects(:report).once.with do |error, context|
        assert_equal Instrumentation::Model::IdentifierError, error.class
        assert_equal "user.login", context[:action]
      end
      assert_raises(Instrumentation::Model::IdentifierError) do
        @free_user.instrument(:login, { user: @free_user, user_id: @free_user.id + 1 })
      end
    end

    test "marks the field as invalid" do
      GitHub.stubs(:audit_log_raise_on_verify?).returns(false)
      events = subscribe "user.login"
      expected_payload = {
        user: "#{@github.name_with_owner}",
        user_id: @github.id,
        # Why is this here??? Because we're passing a repo shaped object as an argument
        # and in the event expansion we add repo visibility in event context.
        public_repo: @github.public?,
      }.tap do |p|
        unless GitHub.single_business_environment?
          p[:data] ||= {}
          p[:data][:_invalid] = true
        end
      end
      @free_user.instrument(:login, { user: @github })

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  test "new user is on the GitHub default plan" do
    begin
      GitHub.stubs default_plan_name: "giga"
      assert_equal "giga", create(:user).plan.name
    end
  end

  if GitHub.enterprise?
    test "seats count excludes ghost user" do
      begin
        GitHub::Enterprise.license.expire_at = DateTime.now
        count = GitHub::Enterprise.license.seats_used
        assert User.ghost
        assert_equal count, GitHub::Enterprise.license.seats_used
      ensure
        GitHub::Enterprise.license_reset!
      end
    end

    test "seats count excludes suspended users" do
      begin
        GitHub::Enterprise.license.expire_at = DateTime.now
        count = GitHub::Enterprise.license.seats_used
        create(:user, login: "bob", suspended_at: Time.now)
        assert User.find_by_login("bob")
        assert_equal count, GitHub::Enterprise.license.seats_used
      ensure
        GitHub::Enterprise.license_reset!
      end
    end

    test "do not enforce seat count limit during import" do
      GitHub.importing do
        user = User.new
        user.email = "jonmagic@gmail.com"
        user.login = "jonmagic"
        user.password = GitHub.default_password
        user.expects(:enforce_seat_limit).never
        user.save!
      end
    end

    test "active sessions revoked when suspended" do
      begin
        GitHub::Enterprise.license.expire_at = DateTime.now
        user = create(:user, login: "bob")

        session = create(:user_session, user: user)
        assert session.active?, "active session expected"
        refute session.revoked?, "session should not be revoked"

        user.suspend "ok"
        session.reload
        refute session.active?, "inactive session expected"
        assert session.revoked?, "session should be revoked"
      ensure
        GitHub::Enterprise.license_reset!
      end
    end

    test "should not add ghost user to the search index" do
      assert_enqueued_jobs 0, only: AddToSearchIndexJob, queue: :index_high do
        create_user(login: GitHub.ghost_user_login)
      end
    end
  end

  if GitHub.enterprise?
    test "does not enqueue recalculate user discussions job" do
      user = create(:user)
      RecalculateUserDiscussionsJob.expects(:perform_later).never

      user.suspend "ok"
    end
  else
    test "enqueues recalculate user discussions job" do
      user = create(:user)
      RecalculateUserDiscussionsJob.expects(:perform_later).with(user).once

      user.suspend "ok"
    end
  end

  if GitHub.enterprise?
    test "when enabled, preview features are not visible to staff" do
      GitHub.preview_features_enabled = true
      @staffer.update!(gh_role: "staff")
      refute @staffer.preview_features?
    end
  else
    # Members of the gh_role staff are also employees; which defines if
    # preview_features are enabled.
    test "when enabled, preview features are visible to staff" do
      GitHub.preview_features_enabled = true
      @staffer.update!(gh_role: "staff")
      assert @staffer.preview_features?
    end
  end
  test "when enabled, preview features are visible to preview team members" do
    GitHub.preview_features_enabled = true
    if GitHub.enterprise?
      assert feature_team("sekret-enterprise-features-Gvr6pqN").member?(preview_user)
      refute feature_team("Employees").member?(preview_user)
    else
      assert feature_team("Employees").member?(preview_user)
      refute feature_team("sekret-enterprise-features-Gvr6pqN").member?(preview_user)
    end
    assert preview_user.preview_features?
  end

  test "when enabled, preview features are not visible to non-staff" do
    GitHub.preview_features_enabled = true
    @staffer.update!(gh_role: nil)
    remove_as_employee(@staffer)
    assert !@staffer.preview_features?
  end

  test "when disabled, preview features aren't visible to preview team members" do
    GitHub.preview_features_enabled = false
    if GitHub.enterprise?
      assert feature_team("sekret-enterprise-features-Gvr6pqN").member?(preview_user)
      refute feature_team("Employees").member?(preview_user)
    else
      assert feature_team("Employees").member?(preview_user)
      refute feature_team("sekret-enterprise-features-Gvr6pqN").member?(preview_user)
    end
    refute preview_user.preview_features?
  end

  context "disabled_orgs relation" do
    test "returns orgs owned by the user, on a paid plan, that are disabled" do
      user = @free_user
      member_paid_disabled_org = create(:organization, disabled: true)
      member_paid_disabled_org.add_member(user)
      owned_paid_non_disabled_org = create(:organization, admin: user)
      owned_paid_disabled_org = create(:organization, admin: user, disabled: true)
      owned_free_disabled_org = create(:free_organization, admin: user, disabled: true)
      unrelated_paid_disabled_org = create(:organization, disabled: true)

      assert_equal [owned_paid_disabled_org], user.disabled_orgs
    end
  end

  if GitHub.enterprise?
    test "saves raw logins provided to create" do
      GitHub.auth.stubs(:external?).returns(true)
      user = User.create_with_random_password "you@example.org"

      assert_equal [], user.errors.full_messages
      assert_equal "you@example.org", user.raw_login
      assert_equal "you", user.login

      user.destroy
    end

    test "a login is valid if raw_login or normalized login match" do
      GitHub.auth.stubs(:external?).returns(true)
      user = User.create_with_random_password "one_two"

      assert_equal [], user.errors.full_messages
      assert_equal "one_two", user.raw_login
      assert_equal "one-two", user.login

      assert user.valid_login?("one_two")
      assert user.valid_login?("one-two")
      assert !user.valid_login?("onetwo")
    end

    test ".create_with_random_password fails when login is blank" do
      GitHub.auth.stubs(:external?).returns(true)
      user = User.create_with_random_password ""

      assert_includes user.errors.full_messages, "Username can't be blank"
    end

    test "not first run if more than one seat is used" do
      GitHub.auth.stubs(:external?).returns(true)
      GitHub::Enterprise.license.stubs(:seats_used).returns(2)

      refute GitHub.enterprise_first_run?
    end

    test "creates user as staff for first external auth login" do
      GitHub.auth.stubs(:external?).returns(true)
      GitHub.stubs(:enterprise_first_run?).returns(true)
      entry = Net::LDAP::Entry.new("foo")

      user = nil
      assert_difference("User.count") do
        user, message = GitHub::Authentication::LDAP.new.create_user("bob", entry)
      end
      assert user.site_admin?
    end

    test "creates normal user if not first external auth login" do
      GitHub.auth.stubs(:external?).returns(true)
      GitHub.stubs(:enterprise_first_run?).returns(false)

      user = nil
      assert_difference("User.count") do
        user = User.create_with_random_password("bob")
      end
      assert !user.site_admin?
    end
  end

  context "reserved login" do
    test "unlisted login" do
      user = User.new login: "waltersobchak"
      refute user.login_reserved?
    end

    test "listed login" do
      user = User.new login: "explore"
      assert user.login_reserved?

      user.login = "Explore"
      assert user.login_reserved?
    end

    test "disallows chat username", skip_enterprise: true do
      user = User.new(login: "chat")
      assert_predicate user, :login_reserved?
    end

    if GitHub.enterprise?
      test "allows chat username" do
        user = User.new(login: "chat")
        refute_predicate user, :login_reserved?
      end
    end

    test "dynamic error code login" do
      codes = (400..431).to_a + (500..511).to_a
      codes.each do |code|
        user = User.new(login: code.to_s)
        assert user.login_reserved?
      end
    end

    unless GitHub.enterprise?
      test "listed non-Enterprise login" do
        %w[octicons avatars].each do |login|
          user = User.new(login: login)
          assert user.login_reserved?
        end
      end

      test "dynamic view-directory login" do
        %w[issues labels oauth_accesses seats].each do |login|
          user = User.new(login: login)
          assert user.login_reserved?
        end
      end
    end

    test "validation passes" do
      user = create_user(login: "walter-sobchak")
      assert_valid user
    end

    test "validation fails" do
      user = create_user(login: "explore")
      assert user.errors[:login].any?
    end

    test "integrations user" do
      user = create_user(login: "integrations")
      assert_valid user
    end

    test "message for reserved login validation is user-friendly" do
      user = create_user(login: "admin")

      assert_equal "admin", user.login
      assert_equal "admin", user.display_login
      assert user.errors[:login].any?
      assert_includes user.errors.full_messages, "Username 'admin' is unavailable"
    end
  end

  test "detect education coupon codes" do
    student_coupon = build :coupon, code: "students-2014", discount: 0.5, group: "education-individual"
    teacher_coupon = build :coupon, code: "teachers-2014", discount: 0.5, group: "education-individual"
    classroom_coupon = build :coupon, code: "classroom-2014", discount: 0.5, group: "education-org"

    user = create(:user)

    refute user.education?

    user = create(:user)
    user.coupons.push student_coupon

    assert user.education?

    user = create(:user)
    user.coupons.push teacher_coupon
    assert user.education?

    user = create(:user)
    user.coupons.push classroom_coupon
    assert user.education?
  end

  test "detects student developer pack coupon" do
    student_developer_pack_coupon = build(:coupon, code: "students-dev-pack", discount: 0.5, group: "education-individual", duration: 29970)
    user = create(:user)

    user.coupons.push student_developer_pack_coupon

    assert user.student_developer_pack_coupon?
  end

  test "detects no student developer pack coupon" do
    invalid_coupon = build(:coupon, code: "not-students-dev-pack", discount: 0.5, group: "education-individual", duration: 29970)
    user = create(:user)

    user.coupons.push invalid_coupon

    assert user.has_an_active_coupon?
    refute user.student_developer_pack_coupon?
  end

  test "detect education emails" do
    user = create :user, email: "github@harvard.edu"
    assert user.education?

    user = create :user, email: "github@ox.ac.uk"
    assert user.education?

    user = create :user, email: "foo@github.com"
    refute user.education?
  end

  test "return true for new user" do
    user = create(:user)
    assert user.is_new?
  end

  test "return false for old user" do
    user = create(:old_user)
    refute user.is_new?
  end

  context "find_repo_by_name" do
    include GitHub::DatabaseQueryWarningsTestHelpers

    test "returns repository" do
      user = create(:user)
      repository = create :repository, owner: user, name: "repo-name"

      assert_equal repository, (user.find_repo_by_name("repo-name"))
    end

    test "returns nil for unknown repo" do
      user = create(:user)
      assert_nil(user.find_repo_by_name("nonexistant-repo"))
    end

    test "returns nil for non 3 byte UTF-8" do
      user = create(:user)
      assert_no_query_warnings do
        assert_nil(user.find_repo_by_name("emoji-🎃"))
      end
    end
  end

  context "teams" do
    test "users belong to teams" do
      @paid_org_team.add_member @free_user
      assert_equal [@paid_org_team], @free_user.teams
    end

    test "users belong to teams and excludes their ancestors by default" do
      parent_team = create :team, organization: @paid_org,  privacy: :closed, name: "parent-team"
      child_team  = create :team, organization: @paid_org,  privacy: :closed, name: "child-team", parent_team_id: parent_team.id
      child_team.add_member @free_user
      assert_same_elements [child_team], @free_user.teams
    end

    test "users belong to teams and includes their ancestors" do
      parent_team = create :team, organization: @paid_org,  privacy: :closed, name: "parent-team"
      child_team  = create :team, organization: @paid_org,  privacy: :closed, name: "child-team", parent_team_id: parent_team.id
      child_team.add_member @free_user
      assert_same_elements [parent_team, child_team], @free_user.teams(with_ancestors: true)
    end

    test "users belong to teams using abilities" do
      @paid_org_team.add_member @free_user
      assert_able @free_user, :read, @paid_org_team
    end

    test "users only belong to teams they are members of, not teams they only have admin on via the org" do
      @paid_org.add_member @free_user, action: :admin
      other_team = create(:team, organization: @paid_org)
      @paid_org_team.add_member @free_user
      assert_equal [@paid_org_team], @free_user.teams
    end

    test "user teams can be constrained by organization" do
      other_org = create(:organization, admin: @staffer, plan: GitHub::Plan.non_free_org_plans.first.name)
      other_team = create(:team, organization: other_org)
      @paid_org_team.add_member @free_user
      other_team.add_member @free_user

      assert_same_elements [@paid_org_team, other_team], @free_user.teams
      assert_equal [@paid_org_team], @free_user.teams.owned_by(@paid_org)
    end

    test "deleting removes user from teams" do
      @paid_org_team.add_member @free_user
      @free_user.destroy
      refute @paid_org_team.members.include? @free_user
    end
  end

  context "async_teams" do
    test "users belong to teams" do
      @paid_org_team.add_member @free_user
      assert_same_elements [@paid_org_team], @free_user.async_teams.sync
    end

    test "users belong to teams and excludes their ancestors by default" do
      parent_team = create :team, organization: @paid_org,  privacy: :closed, name: "parent-team"
      child_team  = create :team, organization: @paid_org,  privacy: :closed, name: "child-team", parent_team_id: parent_team.id
      child_team.add_member @free_user
      assert_same_elements [child_team], @free_user.async_teams.sync
    end

    test "users belong to teams and includes their ancestors" do
      parent_team = create :team, organization: @paid_org,  privacy: :closed, name: "parent-team"
      child_team  = create :team, organization: @paid_org,  privacy: :closed, name: "child-team", parent_team_id: parent_team.id
      child_team.add_member @free_user
      assert_same_elements [parent_team, child_team], @free_user.async_teams(with_ancestors: true).sync
    end

    test "user teams can be constrained by organization" do
      other_org = create(:organization, admin: @staffer, plan: GitHub::Plan.non_free_org_plans.first.name)
      other_team = create(:team, organization: other_org)
      @paid_org_team.add_member @free_user
      other_team.add_member @free_user

      assert_same_elements [@paid_org_team, other_team], @free_user.async_teams.sync
      assert_same_elements [@paid_org_team], @free_user.async_teams.sync.owned_by(@paid_org)
    end
  end

  context "member_repositories" do
    test "returns collaborating repos" do
      @grit.add_member @paid_user
      assert_equal [@grit], @paid_user.member_repositories
    end

    test "does not include org repos" do
      org_repo = create(:repository, owner: @paid_org)
      @paid_org_team.add_repository org_repo, :pull
      @paid_org_team.add_member @paid_user
      @grit.add_member @paid_user

      assert org_repo.pullable_by? @paid_user
      assert_equal [@grit], @paid_user.member_repositories
    end

    test "all_repositories_count" do
      @facebox.add_member @free_user
      assert_equal 2, @free_user.all_repositories_count
    end
  end

  context "outside_collaborator_repositories" do
    test "returns collaborating repositories owned by business" do
      business = create(:business)
      org = create(:organization, plan: GitHub::Plan.business_plus, seats: 10)
      business.add_organization(org)
      org_repo = create(:repository, owner: org)
      org_repo.add_member(@free_user)

      assert_equal [org_repo], @free_user.outside_collaborator_repositories(business: business)
    end

    test "returns forks part of business-owned private repository networks" do
      org_user = create(:user)
      outside_user = create(:user)

      business = create(:business)
      org = create(:organization, plan: GitHub::Plan.business_plus, seats: 10, admin: org_user)
      org.allow_private_repository_forking(actor: org_user)
      business.add_organization(org)

      org_repo = create(:private_repository, owner: org, from_example: :simple)

      user_fork = create(:fork_repository, forker: org_user, fork_repo: org_repo)
      user_fork.add_member(outside_user)

      assert_equal [user_fork], outside_user.outside_collaborator_repositories(business: business)
    end
  end

  context "collaborators_count" do
    test "returns members of owned private repos for users" do
      pub_repo = create :repository, owner: @paid_user, name: "pub-repo"
      priv_repo = create(:private_repository, owner: @paid_user, name: "priv-repo")

      pub_collab = create(:user)
      priv_collab = create(:user)

      pub_repo.add_member pub_collab
      priv_repo.add_member priv_collab

      count, queries = log_cleaned_queries { @paid_user.collaborators_count }
      assert_equal 1, count
      assert queries.map(&:sql).any? { |sql| sql.include?("FORCE INDEX") }
    end

    test "returns members of owned private repos for orgs" do
      public_repo = create(:repository, owner: @paid_org, name: "public-repo")
      private_repo = create(:private_repository, owner: @paid_org, name: "private-repo")

      public_repo_collaborator = create(:user, login: "public-repo-collaborator")
      public_repo.add_member(public_repo_collaborator)

      private_repo_collaborator = create(:user, login: "private-repo-collaborator")
      private_repo.add_member(private_repo_collaborator)

      public_repo_team = create(:team, organization: @paid_org, name: "public-repo-team")
      public_repo_team_member = create(:user, login: "public-repo-team-member")
      public_repo_team.add_repository(public_repo, :pull)
      public_repo_team.add_member(public_repo_team_member)

      private_repo_team = create(:team, organization: @paid_org, name: "private-repo-team")
      private_repo_team_member = create(:user, login: "private-repo-team-member")
      private_repo_team.add_repository(private_repo, :pull)
      private_repo_team.add_member(private_repo_team_member)

      assert_equal 1, @paid_org.collaborators_count
    end
  end

  context "password reset email addresses" do
    test "other user's email addresses are not usable" do
      refute @staffer.is_password_reset_email?(@free_user.email)
    end

    context "with one or more verified email addresses" do
      test "default email address is usable" do
        @staffer.emails.create!(email: "staffer@github.com", state: "verified")

        assert @staffer.is_password_reset_email?(@staffer.email)
      end

      if GitHub.email_verification_enabled?
        test "unverified address is not usable if email verification is enabled" do
          @staffer.emails.create!(email: "staffer@github.com", state: "verified")
          @staffer.add_email("staffer@defunktion.com")

          refute @staffer.is_password_reset_email?("staffer@defunktion.com")
        end
      else
        test "unverified address is usable if email verification is disabled" do
          @staffer.emails.create!(email: "staffer@github.com", state: "verified")
          @staffer.add_email("staffer@defunktion.com")

          assert @staffer.is_password_reset_email?("staffer@defunktion.com")
        end
      end

      test "verified address is usable" do
        @staffer.emails.create!(email: "staffer@github.com", state: "verified")

        assert @staffer.is_password_reset_email?("staffer@github.com")
      end

      test "verified address is usable if set as backup" do
        backup_email = @staffer.emails.create!(email: "staffer@github.com", state: "verified")
        @staffer.set_backup_email(backup_email)

        assert @staffer.is_password_reset_email?("staffer@github.com")
      end

      test "verified address is not usable if different address set as backup" do
        @staffer.emails.create!(email: "verified@github.com", state: "verified")
        backup_email = @staffer.emails.create!(email: "staffer@github.com", state: "verified")

        @staffer.set_backup_email(backup_email)

        refute @staffer.is_password_reset_email?("verified@github.com")
      end

      test "verified address is not usable if user only wants passwords resets sent to primary" do
        @staffer.emails.create!(email: "staffer@github.com", state: "verified")
        @staffer.allow_password_reset_with_primary_email_only

        refute @staffer.is_password_reset_email?("staffer@github.com")
      end

      test "primary address is usable if user only wants passwords resets sent to primary" do
        @staffer.emails.create!(email: "staffer@github.com", state: "verified")
        @staffer.allow_password_reset_with_primary_email_only

        assert @staffer.is_password_reset_email?(@staffer.email)
      end

      test "does not consider unicode normalized values as identical" do
        unicode = "ſ" + @staffer.email[1..-1]

        # lookup succeeds, because of normalization
        assert_equal(@staffer, User.find_by_email(unicode))
        # confirm ruby string comparison doesn't normalize values
        refute_equal unicode, @staffer.email
        # even after upcasing
        refute_equal unicode.upcase(:ascii), @staffer.email.upcase(:ascii)
        # but is not considered valid
        refute @staffer.is_password_reset_email?(unicode)
      end

      test "email lookup is case insensitive" do
        assert @staffer.is_password_reset_email?(@staffer.email.upcase)
      end
    end

    # Use Timecop to visit the future so we're outside of the 30-minute window
    # after the account is created in which all addresses are considered
    # verified.
    context "with no verified email addresses" do
      test "default email address is usable" do
        Timecop.freeze(1.hour.from_now) do
          assert @staffer.is_password_reset_email?(@staffer.email)
        end
      end

      # Enterprise doesn't do email verification.
      unless GitHub.enterprise?
        test "unverified address is usable" do
          unverified_email = @staffer.add_email("staffer@defunktion.com")
          refute unverified_email.primary?
          refute unverified_email.backup_role?

          Timecop.freeze(1.hour.from_now) do
            assert @staffer.is_password_reset_email?("staffer@defunktion.com")
          end
        end
      end
    end
  end

  context "known email addresses" do
    test "user entered email addresses are known" do
      @staffer.add_email("staffer@defunktion.com")

      assert @staffer.is_known_email?("staffer@defunktion.com")
    end

    test "stealth email addresses are not known" do
      user = create(:user)
      stealth_email = StealthEmail.new(user)
      stealth_email.save!

      refute user.is_known_email?(stealth_email.email)
    end

    test "other users' addresses are not known" do
      refute @staffer.is_known_email?(@free_user.email)
    end
  end

  context "#public_attribution_email" do
    test "uses profile email if present" do
      @free_user.create_profile(email: "free_user@bar.com")
      assert_equal "free_user@bar.com", @free_user.public_attribution_email
    end

    test "uses stealth email if profile email is nil" do
      @free_user.create_profile(email: nil)
      assert_equal "#{@free_user.id}+free-user@users.noreply.github.com", @free_user.public_attribution_email
    end

    test "uses stealth email if profile email is empty string" do
      @free_user.create_profile(email: "")
      assert_equal "#{@free_user.id}+free-user@users.noreply.github.com", @free_user.public_attribution_email
    end

    test "uses stealth email if no profile exists" do
      assert_equal "#{@free_user.id}+free-user@users.noreply.github.com", @free_user.public_attribution_email
    end
  end

  context "invited_organizations" do
    test "only returns organizations that the user is invited to" do
      user = create(:user)

      invited_org = create(:organization, login: "invited-org")
      invited_org.invite(user, inviter: invited_org.admins.first, teams: [create(:team, organization: invited_org)])

      accepted_org = create(:organization, login: "accepted-org")
      invitation   = accepted_org.invite(user, inviter: accepted_org.admins.first, teams: [create(:team, organization: accepted_org)])
      invitation.accept

      already_member_org = create(:organization, login: "already-member-org")
      create(:team, organization: already_member_org).add_member(user)

      assert_equal [invited_org], user.invited_organizations
    end

    test "does not return soft-deleted organizations the user has been invited to", skip_enterprise: true do
      user = create(:user)

      invited_org = create(:organization, login: "invited-org")
      invited_org.invite(user, inviter: invited_org.admins.first, teams: [create(:team, organization: invited_org)])

      # Should not be included in the list.
      soft_deleted_inviting_org = create(:organization, :soft_deleted, login: "soft-deleted-inviting-org")
      soft_deleted_inviting_org.invite(user, inviter: soft_deleted_inviting_org.admins.first, teams: [create(:team, organization: soft_deleted_inviting_org)])

      assert_equal [invited_org], user.invited_organizations
    end
  end

  context "can_send_invitations_for?" do
    test "true for org admins when no teams are specified" do
      org_admin = create(:user, login: "org-admin")
      org       = create(:organization, admin: org_admin)

      assert org_admin.can_send_invitations_for?(org)
    end

    test "true for org admins when a team is specified" do
      org_admin = create(:user, login: "org-admin")
      org       = create(:organization, admin: org_admin)
      team      = create(:team, organization: org)

      assert org_admin.can_send_invitations_for?(org, teams: [team])
    end

    test "true for enterprise admins when the organization belongs to one" do
      org          = create(:organization)
      enterprise   = create(:business)
      enterprise.add_organization(org)
      installation = make_integration_installation(target: enterprise, permissions: { "enterprise_administration" => :write })

      assert installation.bot.can_send_invitations_for?(org.reload)
    end

    test "true when the user is the org itself" do
      org  = create(:organization)
      team = create(:team, organization: org)

      assert org.can_send_invitations_for?(org, teams: [team])
    end

    test "false when the user is a non-admin and no teams are specified" do
      org               = create(:organization)
      admin_team_member = create(:user, login: "admin-team-member")
      admin_team        = create(:team, organization: org, name: "admin-team", permission: "admin")
      admin_team.add_member(admin_team_member)

      refute admin_team_member.can_send_invitations_for?(org)
    end

    test "false when the user is a non-admin and all teams are admin teams and the user isn't on one of them" do
      org               = create(:organization)
      admin_team_member = create(:user, login: "admin-team-member")
      admin_teams       = Array.new(2) { |i| create(:team, organization: org, name: "admin-team-#{i}", permission: "admin") }
      admin_teams.first.add_member(admin_team_member)

      refute admin_team_member.can_send_invitations_for?(org, teams: admin_teams)
    end

    test "false when the user is a non-admin and one of the teams is a non-admin team" do
      org         = create(:organization)
      team_member = create(:user, login: "team-member")

      admin_team = create(:team, organization: org, name: "admin_team", permission: "admin")
      admin_team.add_member(team_member)

      pull_team = create(:team, organization: org, name: "pull_team", permission: "pull")
      pull_team.add_member(team_member)

      refute team_member.can_send_invitations_for?(org, teams: [admin_team, pull_team])
    end

    test "false when the user is a team maintainer" do
      org             = create(:organization)
      team            = create(:team, organization: org)
      team_maintainer = create(:user, login: "team-maintainer")
      org.add_member(team_maintainer)
      team.add_member(team_maintainer)
      team.promote_maintainer(team_maintainer)

      refute team_maintainer.can_send_invitations_for?(org, teams: [team])
    end

    test "false when one of the passed teams isn't on the passed org" do
      org_admin      = create(:user, login: "org-admin")
      org            = create(:organization, admin: org_admin)
      team           = create(:team, organization: org)
      other_org_team = create :team

      refute org_admin.can_send_invitations_for?(org, teams: [team, other_org_team])
    end

    test "false for a billing manager" do
      org_admin      = create(:user, login: "org-admin")
      org            = create(:organization, admin: org_admin)
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org_admin)

      refute billing_manager.can_send_invitations_for?(org)
    end

    test "true when a billing manager is inviting another billing manager" do
      org_admin      = create(:user, login: "org-admin")
      org            = create(:organization, admin: org_admin)
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org_admin)

      assert billing_manager.can_send_invitations_for?(org, role: :billing_manager)
    end

    test "true for installation's bot with write permission on org_members, when no teams are specified" do
      org          = create(:organization)
      github_app   = create(:integration, default_permissions: { "members" => :write })
      installation = make_integration_installation(integration: github_app, target: org)

      assert installation.bot.can_send_invitations_for?(org)
    end

    test "true for installation's bot with write permission on org_members, when a team is specified" do
      org          = create(:organization)
      team         = create(:team, organization: org)
      github_app   = create(:integration, default_permissions: { "members" => :write })
      installation = make_integration_installation(integration: github_app, target: org)

      assert installation.bot.can_send_invitations_for?(org, teams: [team])
    end
  end

  test "initial diff preference is unified" do
    refute @staffer.split_diff_preferred
  end

  test "set diff preference to split" do
    refute @staffer.split_diff_preferred

    @staffer.set_diff_preference(:split)
    assert @staffer.split_diff_preferred
  end

  test "set diff preference to unified" do
    @staffer.set_diff_preference(:split)
    assert @staffer.split_diff_preferred

    @staffer.set_diff_preference(:unified)
    refute @staffer.split_diff_preferred
  end

  context "most_popular_public_repository relation" do
    test "returns the user's active, public repository that has the most stars" do
      user = @free_user
      repo1 = @grit
      repo2 = create(:repository, owner: user)
      repo3 = create(:repository, owner: user)
      private_repo = create(:private_repository, owner: user)
      inactive_repo = create(:repository, owner: user, active: nil)
      other_repo = @facebox # not owned by `user`

      repo1.update!(stargazer_count: 10)
      repo2.update!(stargazer_count: 30)
      repo3.update!(stargazer_count: 20)
      other_repo.update!(stargazer_count: 100)
      private_repo.update!(stargazer_count: 100)
      inactive_repo.update!(stargazer_count: 100)

      assert_equal repo2, user.most_popular_public_repository
    end
  end

  context "most_recent_session scope" do
    test "does not include impersonated sessions" do
      user = create(:user)
      impersonator = create(:staff_admin_user)
      session = build(:user_session, user: user)
      session.impersonator_session = create(:user_session, user: impersonator)
      session.save!

      assert_predicate session, :impersonated?
      assert_predicate user.sessions, :any?
      assert_nil user.most_recent_session, "should not have most recent session"
    end

    test "returns newest sessions first" do
      new_session_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:30 -0700").utc
      old_session_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:29 -0700").utc
      user = create(:user)

      Timecop.freeze(old_session_date) do
        create(:user_session, user: user)
      end

      Timecop.freeze(new_session_date) do
        @session = create(:user_session, user: user)
      end

      assert_predicate user.sessions, :any?
      assert_equal @session, user.most_recent_session
    end
  end

  context "last_active" do
    test "returns No activity if there are no events" do
      assert_equal "No activity", @free_user.last_active
    end

    test "returns date of the most recent event" do
      GitHub.flipper[:discard_stratocaster_fanout].disable
      last_active_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:30 -0700").utc

      Timecop.freeze(last_active_date) do
        repo = nil
        only = [ProcessEventJob, UpdateEventFeedsJob]
        perform_enqueued_jobs(only: only) { repo = create :repository, :full_creation, owner: @free_user }
      end

      assert_equal last_active_date.in_time_zone, @free_user.last_active
      assert_equal last_active_date.in_time_zone, @free_user.last_active_timestamp
      assert_equal last_active_date.in_time_zone, @free_user.last_stratocaster_event_at
    end
  end

  context "last_active_session_at" do
    test "returns nil if there are no sessions" do
      user = create(:user)
      refute_predicate user.sessions, :any?
      assert_nil user.last_active_session_at, "should not have session timestamp"
    end

    test "returns date of the most recent event" do
      last_session_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:30 -0700").utc

      Timecop.freeze(last_session_date) do
        create(:user_session, user: @free_user)
      end

      assert_equal last_session_date.in_time_zone, @free_user.last_active_session_at
    end
  end

  unless GitHub.single_business_environment?
    context "#update_business_user_account_login" do
      test "updates all business user accounts login when user login changes" do
        accounts = (1..5).map { create :business_user_account, user: @free_user }
        @free_user.update!(login: "new-login")

        accounts.each do |account|
          account.reload
          assert_equal @free_user.login, account.login
        end
      end
    end
  end

  context "prerelease agreement" do
    test "prerelease_agreement_signed? returns false if the User has not signed the pre-release agreement" do
      refute @free_user.prerelease_agreement_signed?
    end

    test "prerelease_agreement_signed? returns true if the User has signed the pre-release agreement" do
      PrereleaseProgramMember.create!(member: @free_user, actor: @free_user)
      assert @free_user.prerelease_agreement_signed?
    end

    test "async_org_prerelease_agreement_signed? returns false if the User is not a member of any orgs that have signed the pre-release agreement" do
      org = create(:organization, admin: @free_user)
      refute @free_user.async_org_prerelease_agreement_signed?.sync
    end

    test "async_org_prerelease_agreement_signed? returns true if the User is a member of an org that has signed the pre-release agreement" do
      org = create(:organization, admin: @free_user)
      PrereleaseProgramMember.create!(member: org, actor: @free_user)
      assert @free_user.async_org_prerelease_agreement_signed?.sync
    end
  end

  test "#user? returns true" do
    assert_predicate @free_user, :user?
  end

  test "#organization? returns false" do
    refute_predicate @free_user, :organization?
  end

  test "#bot? returns false" do
    refute_predicate @free_user, :bot?
  end

  test "#mannequin? returns false" do
    refute_predicate @free_user, :mannequin?
  end

  context "#mobile_time_zone" do
    test "returns the ActiveSupport::TimeZone object associated with mobile_time_zone_name" do
      profile = create :profile
      profile.update!(mobile_time_zone_name: "America/Chicago")
      assert_equal ActiveSupport::TimeZone["America/Chicago"], profile.user.mobile_time_zone
    end

    test "returns the default ActiveSupport::TimeZone if mobile_time_zone_name is blank" do
      profile = create :profile
      profile.update!(mobile_time_zone_name: nil)
      assert_equal Time.zone, profile.user.mobile_time_zone
    end

    test "returns the default ActiveSupport::Timezone if user does not have a profile" do
      user = create :user
      assert_nil user.profile
      assert_equal Time.zone, user.mobile_time_zone
    end
  end

  context "default repo visibility" do
    test "is public for a free user on dotcom, private on GHES" do
      expected = GitHub.enterprise? ? "private" : "public"
      assert_equal expected, @free_user.default_repo_visibility
    end

    test "is public for a paid user on dotcom, private on GHES" do
      expected = GitHub.enterprise? ? "private" : "public"
      assert_equal expected, @paid_user.default_repo_visibility
    end

    test "is private for a paid user on dotcom and GHES with active SSO session" do
      external_identity = create(:external_identity, user: @paid_user)
      create(:external_identity_session, external_identity: external_identity)
      assert_equal "private", @paid_user.default_repo_visibility
    end

    test "is public for a paid user with expired SSO session on dotcom, private on GHES" do
      expected = GitHub.enterprise? ? "private" : "public"
      external_identity = create(:external_identity, user: @paid_user)
      create(:external_identity_session, external_identity: external_identity, expires_at: 5.minutes.ago)
      assert_equal expected, @paid_user.default_repo_visibility
    end
  end

  context "destroy_reactions" do
    test "#destroy_reactions destroys all reactions associated with this user" do
      user = create(:user, :verified)
      repository = create(:repository, owner: user, from_example: :simple)
      issue = create(:issue)
      issue_comment = create(:issue_comment)
      commit_comment = create(:commit_comment)
      issue.react(actor: user, content: "heart")
      issue_comment.react(actor: user, content: "+1")
      commit_comment.react(actor: user, content: "tada")
      release = create(:release, repository: repository, author: user)
      create(:reaction, subject: release, user: user)
      create(:discussion_category, repository: repository)
      repository_advisory = create(:repository_advisory)
      create(:reaction, subject: repository_advisory, user: user)
      repository_advisory_comment = create(:repository_advisory_comment)
      create(:reaction, subject: repository_advisory_comment, user: user)
      discussion_post = create(:discussion_post)
      create(:reaction, subject: discussion_post, user: user)
      discussion_post_reply = create(:discussion_post_reply)
      create(:reaction, subject: discussion_post_reply, user: user)
      discussion_comment = create(:discussion_comment)
      discussion_comment.react(actor: user, content: "-1")
      discussion_comment.discussion.react(actor: user, content: "rocket")
      pull_request = create(:pull_request, :with_mergeable_head, repository: repository, user: user)
      pull_request_review = create(:pull_request_review, pull_request: pull_request, repository: repository)
      pull_request_review.react(actor: user, content: "+1")
      pull_request_review_comment = create(:pull_request_review_comment, pull_request: pull_request, repository: repository)
      pull_request_review_comment.react(actor: user, content: "tada")

      assert_equal 1, user.issue_reactions.count
      assert_equal 1, user.issue_comment_reactions.count
      assert_equal 1, user.commit_comment_reactions.count
      assert_equal 1, user.release_reactions.count
      assert_equal 1, user.repository_advisory_reactions.count
      assert_equal 1, user.repository_advisory_comment_reactions.count
      assert_equal 1, user.discussion_post_reactions.count
      assert_equal 1, user.discussion_post_reply_reactions.count
      assert_equal 1, user.pull_request_review_comment_reactions.count
      assert_equal 1, user.pull_request_review_reactions.count
      assert_equal 1, user.discussion_reactions.count
      assert_equal 1, user.discussion_comment_reactions.count

      user.destroy_reactions

      assert_equal 0, user.reload.issue_reactions.count
      assert_equal 0, user.reload.issue_comment_reactions.count
      assert_equal 0, user.commit_comment_reactions.count
      assert_equal 0, user.release_reactions.count
      assert_equal 0, user.repository_advisory_reactions.count
      assert_equal 0, user.repository_advisory_comment_reactions.count
      assert_equal 0, user.discussion_post_reactions.count
      assert_equal 0, user.discussion_post_reply_reactions.count
      assert_equal 0, user.pull_request_review_comment_reactions.count
      assert_equal 0, user.pull_request_review_reactions.count
      assert_equal 0, user.discussion_reactions.count
      assert_equal 0, user.discussion_comment_reactions.count
    end
  end

  context "color_modes" do
    test "#color_mode uses database default" do
      assert_equal create(:user).color_mode, ColorMode::UNSET
    end

    test "#color_mode_with_default returns default color mode if user hasn't picked one" do
      assert_equal create(:user).color_mode_with_default, ColorMode.default
    end

    test "#color_mode_with_default returns user-set value" do
      assert_equal(
        create(:user, color_mode: ColorMode::DARK).color_mode_with_default,
        ColorMode::DARK
      )
    end

    test "#color_mode_toggle_target returns UserTheme::DEFAULT_DARK when color_mode_with_default is LIGHT" do
      assert_equal(
        UserTheme::DEFAULT_DARK,
        create(:user, color_mode: ColorMode::LIGHT).color_mode_toggle_target
      )
    end

    test "#color_mode_toggle_target returns UserTheme::DEFAULT_LIGHT when color_mode_with_default is DARK" do
      assert_equal(
        UserTheme::DEFAULT_LIGHT,
        create(:user, color_mode: ColorMode::DARK).color_mode_toggle_target
      )
    end
  end

  context "#eligible_emails_for" do
    test "returns emails from eligible domains" do
      emails = [
        "olivia@#{@domain.domain}",
        "orisa@#{@other_domain.domain}",
        "orly@#{@approved_domain.domain}",
        "mercy@example.com"
      ]
      emails.each { |email| @staffer.add_email(email).verify! }

      eligible_emails = emails[0..2]
      results = @staffer.eligible_emails_for(@paid_org).map(&:email)
      async_results = @staffer.async_eligible_emails_for(@paid_org).sync.map(&:email)
      assert_same_elements eligible_emails, results
      assert_same_elements eligible_emails, async_results
    end

    test "can just get the verified domain emails" do
      emails = [
        "olivia@#{@domain.domain}",
        "orisa@#{@other_domain.domain}",
        "orly@#{@approved_domain.domain}",
        "mercy@example.com"
      ]
      emails.each { |email| @staffer.add_email(email).verify! }

      verified_domain_emails = emails[0..1]
      results = @staffer.eligible_emails_for(@paid_org, include_approved: false).map(&:email)
      async_results = @staffer.async_eligible_emails_for(@paid_org, include_approved: false).sync.map(&:email)
      assert_same_elements verified_domain_emails, results
      assert_same_elements verified_domain_emails, async_results
    end

    test "can just get the approved domain emails" do
      emails = [
        "olivia@#{@domain.domain}",
        "orisa@#{@other_domain.domain}",
        "orly@#{@approved_domain.domain}",
        "mercy@example.com"
      ]
      emails.each { |email| @staffer.add_email(email).verify! }

      approved_domain_emails = [emails[2]]
      results = @staffer.eligible_emails_for(@paid_org, include_verified: false).map(&:email)
      async_results = @staffer.async_eligible_emails_for(@paid_org, include_verified: false).sync.map(&:email)
      assert_same_elements approved_domain_emails, results
      assert_same_elements approved_domain_emails, async_results
    end

    if GitHub.email_verification_enabled?
      test "only returns verified emails" do
        emails = ["olivia@#{@domain.domain}", "orly@#{@approved_domain.domain}", "mercy@example.com"]
        emails.each { |email| @staffer.add_email(email).verify! }
        @staffer.add_email("orisa@#{@other_domain.domain}")

        verified_eligible_emails = emails[0..1]
        results = @staffer.eligible_emails_for(@paid_org).map(&:email)
        async_results = @staffer.async_eligible_emails_for(@paid_org).sync.map(&:email)
        assert_same_elements verified_eligible_emails, results
        assert_same_elements verified_eligible_emails, async_results
      end
    else
      test "returns unverified emails if email verification is disabled" do
        emails = ["olivia@#{@domain.domain}", "orly@#{@approved_domain.domain}", "mercy@example.com"]
        emails.each { |email| @staffer.add_email(email) }
        @staffer.add_email("orisa@#{@other_domain.domain}")

        expected_results = ["olivia@#{@domain.domain}", "orly@#{@approved_domain.domain}", "orisa@#{@other_domain.domain}"]
        results = @staffer.eligible_emails_for(@paid_org).map(&:email)
        async_results = @staffer.async_eligible_emails_for(@paid_org).sync.map(&:email)
        assert_same_elements expected_results, results
        assert_same_elements expected_results, async_results
      end
    end

    test "returns empty array for user without verified or approved domain emails" do
      member = create(:user)
      member.add_email("mercy@example.com").verify!
      @paid_org.add_member(member)
      assert @paid_org.member?(member)

      assert_empty member.async_eligible_emails_for(@paid_org).sync
      assert_empty member.eligible_emails_for(@paid_org)
    end

    test "returns empty array if user is not a member of org" do
      non_member = create(:user)
      non_member.add_email("acidburn@#{@domain.domain}").verify!
      non_member.add_email("acidburn@#{@approved_domain.domain}").verify!

      assert_empty non_member.async_eligible_emails_for(@paid_org).sync
      assert_empty non_member.eligible_emails_for(@paid_org)
    end

    test "returns empty array for org without verified or approved domains" do
      org = create(:organization, admin: @staffer)
      emails = ["olivia@#{@domain.domain}", "orly@#{@approved_domain.domain}", "mercy@example.com"]
      emails.each { |email| @staffer.add_email(email).verify! }

      assert_empty @staffer.async_eligible_emails_for(org).sync
      assert_empty @staffer.eligible_emails_for(org)
    end

    test "works for a user with an email with no email roles" do
      email_address = "olivia@#{@domain.domain}"
      email = @staffer.add_email(email_address)
      email.verify!
      assert_empty email.email_roles

      results = @staffer.eligible_emails_for(@paid_org).map(&:email)
      async_results = @staffer.async_eligible_emails_for(@paid_org).sync.map(&:email)
      assert_same_elements [email_address], results
      assert_same_elements [email_address], async_results
    end

    test "does not return emails that are hard bounced" do
      email = @staffer.add_email("olivia@#{@domain.domain}")
      email.verify!
      email.mark_as_bouncing!
      assert_predicate email, :bouncing?

      assert_empty @staffer.async_eligible_emails_for(@paid_org).sync
      assert_empty @staffer.eligible_emails_for(@paid_org)
    end
  end

  context "#like_login_or_profile_name scope" do
    test "correctly selects users by login" do
      user1 = create(:user, login: "user-query-1")
      user2 = create(:user, login: "user-query-2")
      user3 = create(:user, login: "user-not-1")
      user4 = create(:user, login: "user-not-2")

      users = User.like_login_or_profile_name("-query-")
      assert_same_elements [user1, user2], users

      users = User.like_login_or_profile_name("-not-")
      assert_same_elements [user3, user4], users
    end

    test "correctly selects users by profile name" do
      user1 = create(:user, login: "user-query-1")
      user1.profile = create(:profile, name: "User Jamba")
      user1.save
      user2 = create(:user, login: "user-query-2")
      user2.profile = create(:profile, name: "User Jambala")
      user2.save
      user3 = create(:user, login: "user-not-1")
      user3.profile = create(:profile, name: "User Dumbo")
      user3.save
      user4 = create(:user, login: "user-not-2")
      user4.profile = create(:profile, name: "User Dumbolo")
      user4.save

      users = User.like_login_or_profile_name("jamba")
      assert_same_elements [user1, user2], users

      users = User.like_login_or_profile_name("dumbo")
      assert_same_elements [user3, user4], users
    end

    test "correctly selects users by login or profile name" do
      user1 = create(:user, login: "user-query-1")
      user1.profile = create(:profile, name: "User Jamba")
      user1.save
      user2 = create(:user, login: "user-query-2")
      user2.profile = create(:profile, name: "User Jambala")
      user2.save
      user3 = create(:user, login: "user-not-1")
      user3.profile = create(:profile, name: "User Query")
      user3.save
      user4 = create(:user, login: "user-not-2")
      user4.profile = create(:profile, name: "User not-able")
      user4.save

      users = User.like_login_or_profile_name("query")
      assert_same_elements [user1, user2, user3], users
    end

    test "sanitizes underscores in query" do
      query = User.like_login_or_profile_name("monalisa_fab").to_sql
      assert_includes query, "users.login LIKE '%monalisa\\\\_fab%'"
      refute_includes query, "monalisa_fab"
    end
  end

  context "unlock users on downgrade" do
    test "when user is upgraded to pro, their billing_attempts do not change" do
      user = create :user, plan: "free"
      user.billing_attempts = 1
      user.plan = "pro"
      user.save
      assert_equal 1, user.billing_attempts
      assert_equal "pro", user.plan.name

    end
  end

  context "#outbound_email" do
    test "matches email of a user" do
      assert_equal @owner.email, @owner.outbound_email
    end
  end

  context "business_id" do
    test "allows non zero business_id if multi_tenant_business_id = true" do
      GitHub.stubs(:multi_tenant_business_id?).returns(true)

      user1 = create_user(business_id: 1)
      user2 = create_user

      assert user1.valid?
      assert_equal 1, user1.business_id
      assert user2.valid?
      assert_equal 0, user2.business_id
    end

    test "does not allow non zero business_id if multi_tenant_business_id = false" do
      GitHub.stubs(:multi_tenant_business_id?).returns(false)

      user1 = create_user(business_id: 1)
      user2 = create_user

      refute user1.valid?
      assert_includes user1.errors[:business_id], "must be equal to 0"
      assert user2.valid?
      assert_equal 0, user2.business_id
    end

    test "disallows update to business_id" do
      user = create_user
      user.update(business_id: 1)
      user.save

      refute user.valid?
      assert_includes user.errors[:business_id], "cannot be changed"
    end
  end

  context "#scope_to_current_tenant?" do
    test "false for non multi tenant environments" do
      refute_predicate User, :scope_to_current_tenant?
    end
  end

  context "#display_login" do
    test "sets display_login based on login when login set" do
      u = User.new
      refute u.read_attribute(:display_login)
      u.login = "foo"
      assert_equal "foo", u.read_attribute(:display_login)
    end

    test "overrides display_login when changed to non-login value" do
      user = create_user
      user.update(display_login: "foo")
      refute_equal user.read_attribute(:display_login), "foo"
      assert_equal user.read_attribute(:display_login), User.to_display_login(user.login)
    end

    test "updates display_login when login changes" do
      user = create_user
      refute_equal "foo", user.read_attribute(:display_login)
      user.update(login: "foo")
      assert_equal "foo", user.read_attribute(:display_login)
    end

    test "fails validation when display_login is not a valid login" do
      user = create_user
      user.expects(:set_display_login).once.returns(nil)
      user.update(display_login: "foo")

      assert_equal 1, user.errors.count
      assert_equal "cannot change display_login to value that doesn't correspond to login", user.errors.messages[:display_login].first
    end

    test "returns login when no tenant", skip_enterprise: true do
      GitHub::CurrentTenant.remove

      user1 = create :emu
      assert_equal user1.login, user1.display_login

      user2 = create :user
      assert_equal user2.login, user2.display_login
    end

    test "does not include tenant shortcode suffix in multi-tenant env", skip_enterprise: true do
      business1 = create :business, business_type: :enterprise_managed, shortcode: "fab"
      business2 = create :business, business_type: :enterprise_managed, shortcode: "con"
      refute_equal(business1, business2)

      on_multi_tenant_enterprise do
        GitHub::CurrentTenant.set(business1)
        user1 = create :emu, login: "mtodd", business: business1
        GitHub::CurrentTenant.remove
        assert_equal "mtodd", user1.display_login

        GitHub::CurrentTenant.set(business2)
        user2 = create :emu, login: "mtodd", business: business2
        GitHub::CurrentTenant.remove
        assert_equal "mtodd", user2.display_login
      end
    end

    test "does include tenant shortcode suffix in GHEC", skip_enterprise: true do
      user1 = create :emu, login: "mtodd"
      business1 = user1.enterprise_managed_business
      assert_equal "mtodd_#{business1.shortcode}", user1.display_login

      user2 = create :emu, login: "mtodd"
      business2 = user2.enterprise_managed_business
      assert_equal "mtodd_#{business2.shortcode}", user2.display_login

      refute_equal(business1, business2)
    end
  end

  context "#to_display_login" do
    test "returns login outside of multi-tenant env", skip_in_multitenant_mode: true do
      assert_equal "monalisa", User.to_display_login("monalisa")
      assert_equal "mtodd_fab", User.to_display_login("mtodd_fab")
      assert_equal "joshmgross_con", User.to_display_login("joshmgross_con")
    end

    test "does not include tenant shortcode suffix in multi-tenant env", skip_enterprise: true do
      business1 = create :business, business_type: :enterprise_managed, shortcode: "fab"
      business2 = create :business, business_type: :enterprise_managed, shortcode: "con"
      refute_equal(business1, business2)

      on_multi_tenant_enterprise do
        GitHub::CurrentTenant.remove
        assert_equal "monalisa", User.to_display_login("monalisa")
        assert_equal "mtodd", User.to_display_login("mtodd_fab")
        assert_equal "joshmgross", User.to_display_login("joshmgross_con")

        GitHub::CurrentTenant.set(business1) do
          assert_equal "monalisa", User.to_display_login("monalisa")
          assert_equal "mtodd", User.to_display_login("mtodd_fab")
          assert_equal "joshmgross", User.to_display_login("joshmgross_con")
        end

        GitHub::CurrentTenant.set(business2) do
          assert_equal "monalisa", User.to_display_login("monalisa")
          assert_equal "mtodd", User.to_display_login("mtodd_fab")
          assert_equal "joshmgross", User.to_display_login("joshmgross_con")
        end
      end
    end

    test "includes tenant shortcode suffix when on stafftools", skip_enterprise: true do
      GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)

      on_multi_tenant_enterprise do
        assert_equal "monalisa", User.to_display_login("monalisa")
        assert_equal "mtodd_fab", User.to_display_login("mtodd_fab")
        assert_equal "joshmgross_con", User.to_display_login("joshmgross_con")
      end
    end

    test "does not remove invalid suffixes in multi-tenant env", skip_enterprise: true do
      on_multi_tenant_enterprise do
        assert_equal "monalisa_abc_def", User.to_display_login("monalisa_abc_def")
        assert_equal "mtodd__", User.to_display_login("mtodd__")
        assert_equal "joshmgross_#123", User.to_display_login("joshmgross_#123")
      end
    end

    test "does not remove admin suffix", skip_enterprise: true do
      on_multi_tenant_enterprise do
        assert_equal "fab_admin", User.to_display_login("fab_admin")
      end
    end
  end

  context "#to_param" do
    test "returns login when no tenant", skip_enterprise: true do
      GitHub::CurrentTenant.remove

      user1 = create :emu
      assert_equal user1.login, user1.to_param

      user2 = create :user
      assert_equal user2.login, user2.to_param
    end

    test "does not include tenant shortcode suffix in muli-tenant env", skip_enterprise: true do
      business1 = create :business, business_type: :enterprise_managed, shortcode: "fab"
      business2 = create :business, business_type: :enterprise_managed, shortcode: "con"
      refute_equal(business1, business2)

      on_multi_tenant_enterprise do
        GitHub::CurrentTenant.set(business1)
        user1 = create :emu, login: "mtodd", business: business1
        GitHub::CurrentTenant.remove
        assert_equal "mtodd", user1.to_param

        GitHub::CurrentTenant.set(business2)
        user2 = create :emu, login: "mtodd", business: business2
        GitHub::CurrentTenant.remove
        assert_equal "mtodd", user2.to_param
      end
    end

    test "does include tenant shortcode suffix in GHEC", skip_enterprise: true do
      user1 = create :emu, login: "mtodd"
      business1 = user1.enterprise_managed_business
      assert_equal "mtodd_#{business1.shortcode}", user1.to_param

      user2 = create :emu, login: "mtodd"
      business2 = user2.enterprise_managed_business
      assert_equal "mtodd_#{business2.shortcode}", user2.to_param

      refute_equal(business1, business2)
    end
  end

  # High Profile users are defined by the following Trust & Safety criteria:
  # https://github.com/github/trust-safety/blob/main/docs/operations/escalation-procedures/high-profile-escalation.md
  context "#high_profile?" do
    test "false if high profile criteria not met" do
      user = create_user
      user_repo = create :repository, owner: user, name: "user-repo"
      high_profile, high_profile_reason = HighProfileSignals.high_profile_user?(user)

      refute high_profile
      assert_nil high_profile_reason
    end

    test "true if high profile criteria for followers_count is met" do
      user = create_user

      100.times do
        follower = create(:user)
        follower.follow(user)
      end

      high_profile, high_profile_reason = HighProfileSignals.high_profile_user?(user)

      assert high_profile
      assert_equal "User meets criteria threshold: follower count", high_profile_reason
    end

    test "true if high profile criteria met for enterprise customer", skip_enterprise: true do
      emu_user = create :emu
      high_profile, high_profile_reason = HighProfileSignals.high_profile_user?(emu_user)

      assert high_profile
      assert_equal "User meets criteria threshold: current Premium, Premium Plus, or Enterprise customer", high_profile_reason
    end

    test "true if user owns one or more high profile repositories" do
      user = create_user
      user_repo = create :repository, owner: user, name: "user-repo"
      user_high_profile_repo = create :repository, owner: user, name: "user-high-profile-repo"

      50.times do
        forker = create :user
        fork = create(:fork_repository, forker: forker, fork_repo: user_high_profile_repo)
      end

      high_profile, high_profile_reason = HighProfileSignals.high_profile_user?(user)

      assert high_profile
      assert_equal "User meets criteria threshold: owns one or more high profile repositories", high_profile_reason
    end

    test "true with multiple high profile criteria" do
      user = create_user
      user_repo = create :repository, owner: user, name: "user-repo"
      user_high_profile_repo = create :repository, owner: user, name: "user-high-profile-repo"

      50.times do
        forker = create :user
        fork = create(:fork_repository, forker: forker, fork_repo: user_high_profile_repo)
      end

      100.times do
        follower = create(:user)
        follower.follow(user)
      end

      high_profile, high_profile_reason = HighProfileSignals.high_profile_user?(user)

      assert high_profile
      assert_equal "User meets criteria threshold: follower count, owns one or more high profile repositories", high_profile_reason
    end
  end

  context "#tenant_namespacing_enabled?" do
    test "returns false when current tenant is not set" do
      refute_predicate User, :tenant_namespacing_enabled?
    end

    test "returns false when current tenant is set", skip_enterprise: true do
      begin
        business = create :business, :enterprise_managed
        GitHub::CurrentTenant.set(business)
        refute_predicate User, :tenant_namespacing_enabled?
      ensure
        GitHub::CurrentTenant.remove
      end
    end
  end

  context "#private_asset_url" do
    test "returns new-style url when use_new_url is true" do
      assert_equal "#{GitHub.url}/user-attachments/assets/fake-guid", @staffer.private_asset_url(@staffer.id, "fake-guid", true)
    end

    test "returns old-style url when use_new_url is false" do
      assert_equal "#{GitHub.url}/settings/replies/assets/#{@staffer.id}/fake-guid", @staffer.private_asset_url(@staffer.id, "fake-guid", false)
    end
  end
end

class UserMultiTenantTest < GitHub::TestCase
  fixtures do
    on_multi_tenant_enterprise do
      @tenant = create :business, :enterprise_managed
    end
  end

  context "#scope_to_current_tenant?" do
    test "true when current tenant is not set" do
      on_multi_tenant_enterprise do
        assert_predicate User, :scope_to_current_tenant?
      end
    end

    test "true when current tenant is set" do
      on_multi_tenant_enterprise(tenant: @tenant) do
        assert_predicate User, :scope_to_current_tenant?
      end
    end

    test "false when query scoping is disabled" do
      on_multi_tenant_enterprise(tenant: @tenant) do
        GitHub::CurrentTenant.unscope do
          refute_predicate User, :scope_to_current_tenant?
        end
      end
    end
  end

  context "#tenant_namespacing_enabled?" do
    test "returns false when current tenant is not set" do
      GitHub::CurrentTenant.remove
      on_multi_tenant_enterprise do
        refute_predicate User, :tenant_namespacing_enabled?
      end
    end

    test "returns true when current tenant is set" do
      on_multi_tenant_enterprise(tenant: @tenant) do
        assert_predicate User, :tenant_namespacing_enabled?
      end
    end
  end

  context "reserved login" do
    test "message for reserved login validation excludes shortcode-suffixed login" do
      on_multi_tenant_enterprise(tenant: @tenant) do
        default_ops = {
          "force_enterprise_managed" => true,
          "login_suffix" => @tenant.shortcode,
          "business_id" => @tenant.id
        }
        user = User.create_with_random_password("admin", false, default_ops)

        assert_equal "admin_#{@tenant.shortcode}", user.login
        assert_equal "admin", user.display_login
        assert user.errors[:login].any?
        assert_includes user.errors.full_messages, "Username 'admin' is unavailable"
      end
    end
  end
end

class EmuUserTest < GitHub::TestCase
  fixtures do
    @owner = create(:emu, login: "owner", email: "owner@example.com")
    @business = @owner.enterprise_managed_business
    @first_emu_owner = @business.find_first_emu_owner

    @emu_business_without_owner = create(:business, :enterprise_managed, :without_enterprise_managed_user_owner)

    @user = create(:user)
    @emu_business_without_owner.create_and_add_first_emu_owner(email: "firstowner@microsoft.com", actor: @user)

    @admin_user = User.find_by_login(@emu_business_without_owner.shortcode + "_admin")
  end

  context "#create_with_random_password" do
    test "User.create new EMU removes tenant name" do
      # email is mandatory for logins
      user = User.create_with_random_password("two@business.com", false, { "email" => "two@business.com", "force_enterprise_managed" => true, "login_suffix" => "bus"  })
      assert_predicate user, :valid?
      assert_empty user.errors[:login]
      assert_empty user.errors.full_messages
      assert_equal "two_bus", user.login
    end

    test "User.create new EMU can end with a hyphen" do
      # email is mandatory for logins
      user = User.create_with_random_password("two-@business.com", false, { "email" => "two-@business.com", "force_enterprise_managed" => true, "login_suffix" => "bus"  })
      assert_predicate user, :valid?
      assert_empty user.errors[:login]
      assert_empty user.errors.full_messages
      assert_equal "two-_bus", user.login
    end

    test "User.create new EMU cannot end with two hyphens" do
      # email is mandatory for logins
      user = User.create_with_random_password("two--@business.com", false, { "email" => "two-@business.com", "force_enterprise_managed" => true, "login_suffix" => "bus"  })
      refute_predicate user, :valid?
      refute_empty user.errors[:login]
    end

    test "User.create new EMU cannot contain invalid characters" do
      # email is mandatory for logins
      user = User.create_with_random_password("tw~~o@business.com", false, { "email" => "two-@business.com", "force_enterprise_managed" => true, "login_suffix" => "bus"  })
      refute_predicate user, :valid?
      refute_empty user.errors[:login]
    end

    test "User.create new EMU removes special char _ from prefix" do
      user = User.create_with_random_password("mona.lisa@business.com", false, { "email" => "mona.lisa@business.com", "force_enterprise_managed" => true, "login_suffix" => "msft"  })
      assert_predicate user, :valid?
      assert_empty user.errors[:login]
      assert_empty user.errors.full_messages
      assert_equal "mona-lisa_msft", user.login
    end

    test "User.create new EMU removes special char dot(.) from prefix" do
      user = User.create_with_random_password("mona_lisa@business.com", false, { "email" => "mona_lisa@business.com", "force_enterprise_managed" => true, "login_suffix" => "msft"  })
      assert_predicate user, :valid?
      assert_empty user.errors[:login]
      assert_empty user.errors.full_messages
      assert_equal "mona-lisa_msft", user.login
    end

    test "User.create new EMU _ regex must be followed by business_name" do
      user = User.create_with_random_password("mona_lisa@business.com", false, { "email" => "mona_lisa@business.com", "force_enterprise_managed" => true, "login_suffix" => ""  })
      # Creates an invalid user
      # _ in EMUs must be followed by a business suffix
      refute_predicate user, :valid?
      assert_equal user.errors[:login][0], User::LOGIN_VALIDATION_MESSAGE_FOR_EMUS
    end
  end

  context "#remove_email" do
    test "set profile email as newsies default email when clearing unverified emails" do
      user = create(:emu)
      remove_email = user.primary_user_email
      profile_email = user.profile.email

      ## add new primary email
      primary_email = user.add_emu_shortcode_to_emails(Sham.email)
      primary_user_email = user.emails.build(email: primary_email)
      primary_user_email.mark_as_verified
      user.set_primary_email primary_user_email

      ## remove old primary email
      assert_enqueued_jobs 1, only: UserContributionsBackfillJob do
        user.remove_email(remove_email)
      end

      settings = GitHub.newsies.settings(user).value
      assert_equal profile_email, settings.email(:global).address
    end

    test "remove old email does not start UserContributionsBackfillJob when do_not_rebuild_contributions is set" do
      user = create(:emu)
      remove_email = user.primary_user_email

      ## add new primary email
      primary_email = user.add_emu_shortcode_to_emails(Sham.email)

      ## remove old primary email
      assert_no_enqueued_jobs do
        user.remove_email(remove_email, do_not_rebuild_contributions: true)
      end
    end
  end

  context "#change_email_enabled?" do
    test "returns false for emu user" do
      refute_predicate @owner, :change_email_enabled?
    end

    test "returns true for first admin user" do
      assert_predicate @admin_user, :change_email_enabled?
    end
  end

  context "#outbound_email" do
    test "matches profile email of a user" do
      assert_equal @owner.profile_email, @owner.outbound_email
      refute_equal @owner.email, @owner.outbound_email
    end

    test "does not contain a shortcode" do
      refute_includes @owner.outbound_email, @business.shortcode
    end

    test "matches profile email of a user for a first emu owner" do
      assert_equal @first_emu_owner.profile_email, @first_emu_owner.outbound_email
      refute_equal @first_emu_owner.email, @first_emu_owner.outbound_email
    end

    test "does not contain a shortcode for first emu owner" do
      refute_includes @first_emu_owner.outbound_email, @business.shortcode
    end
  end

  context "#after_destroy" do
    test "user with explicit org membership has organization membership entries removed after destroy", skip_enterprise: true do
      emu_user = create(:emu, business: @business)
      other_emu_user = create(:emu, business: @business)
      emu_org = create :organization, business: @business, admin: other_emu_user
      emu_org.add_member emu_user

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        assert_difference("OrganizationMembershipEntry.count", -1) do
          emu_user.destroy
        end
      end

      assert_raises ActiveRecord::RecordNotFound do
        User.find(emu_user.id)
      end

      assert_nil OrganizationMembershipEntry.find_by(organization_id: emu_org.id, user_id: emu_user.id)
    end

    test "user with derived org membership has organization membership entries removed after destroy", skip_enterprise: true do
      emu_user = create(:emu, business: @business)
      emu_org = create :organization, business: @business, admin: @first_emu_owner
      external_group = create :external_group, :with_members, users: [emu_user], business: @business
      team = create :team, organization: emu_org
      external_group_team = ExternalGroupTeam.create(external_group: external_group, team: team)
      ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        assert_difference("OrganizationMembershipEntry.count", -1) do
          emu_user.destroy
        end
      end

      assert_raises ActiveRecord::RecordNotFound do
        User.find(emu_user.id)
      end

      assert_nil OrganizationMembershipEntry.find_by(organization_id: emu_org.id)
    end
  end

  test "#releases" do
    assert_equal Release, @owner.releases.model
  end

  test "#release_mentions" do
    assert_equal ReleaseMention, @owner.release_mentions.model
  end
end unless GitHub.single_business_environment?
