# typed: true
# frozen_string_literal: true

require "test_helper"

class MultiTenantUserTest < GitHub::TestCase
  include EnvironmentTestHelper
  include DogstatsTestHelpers

  fixtures do
    @business = create(:business, :enterprise_managed)
    setup_staff_user
  end

  setup do
    on_multi_tenant_enterprise
    GitHub.flipper[:tenant_context_telemetry_query_scoping_metrics].disable
    GitHub.flipper[:tenant_context_telemetry_query_scoping_logging].disable
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  def create_user(options = {})
    User.create({
      login: "user-#{SecureRandom.hex(12)}",
      email: Faker::Internet.email,
      password: GitHub.default_password,
    }.merge(options))
  end

  context "User#find_by" do
    test "gracefully handles non-present logins" do
      GitHub::CurrentTenant.set(@business)

      assert_nil User.find_by(login: nil)
      assert_nil User.find_by(login: "")
    end
  end

  context "User#find_by_login" do
    test "finds correct user based on display login" do
      user = create(:emu, login: "mtodd")
      business = user.enterprise_managed_business
      GitHub::CurrentTenant.set(business)
      shortcode = business.shortcode

      assert_equal "mtodd_#{shortcode}", user.login

      found_user = User.find_by_login("mtodd")
      assert_equal user, found_user
      assert_equal shortcode, found_user.enterprise_managed_business.shortcode
    end

    test "finds correct user based on unique login" do
      user = create(:emu, login: "mtodd")
      business = user.enterprise_managed_business
      GitHub::CurrentTenant.set(business)
      shortcode = business.shortcode

      assert_equal "mtodd_#{shortcode}", user.login

      found_user = User.find_by_login(user.login)
      assert_equal user, found_user
      assert_equal shortcode, found_user.enterprise_managed_business.shortcode
    end

    test "finds correct user when multiple users with same display login exist across tenants" do
      user1 = create(:emu, login: "mtodd")
      business1 = user1.enterprise_managed_business

      user2 = create(:emu, login: "mtodd")
      business2 = user2.enterprise_managed_business

      refute_equal(business1, business2)

      GitHub::CurrentTenant.set(business1)
      assert_equal business1, GitHub::CurrentTenant.get
      found_user = User.find_by_login("mtodd")
      assert_equal  user1, found_user

      GitHub::CurrentTenant.set(business2)
      assert_equal business2, GitHub::CurrentTenant.get
      found_user = User.find_by_login("mtodd")
      assert_equal  user2, found_user
    end

    test "works for system accounts when unscoped" do
      business = create(:emu).enterprise_managed_business
      trusted_oauth_apps_owner = create :organization, login: GitHub.trusted_oauth_apps_org_name
      refute_nil User.ghost
      refute_nil User.staff_user

      GitHub::CurrentTenant.remove

      assert_equal trusted_oauth_apps_owner, Organization.unscoped.find_by_login(GitHub.trusted_oauth_apps_org_name)
      assert_equal User.ghost, User.unscoped.find_by_login(GitHub.ghost_user_login)
      assert_equal User.staff_user, User.unscoped.find_by_login(GitHub.staff_user_login)

      GitHub::CurrentTenant.set(business)

      assert_equal trusted_oauth_apps_owner, Organization.unscoped.find_by_login(GitHub.trusted_oauth_apps_org_name)
      assert_equal User.ghost, User.unscoped.find_by_login(GitHub.ghost_user_login)
      assert_equal User.staff_user, User.unscoped.find_by_login(GitHub.staff_user_login)
    end

    test "works for trusted oauth app owner when scoped" do
      business = create(:emu).enterprise_managed_business
      trusted_oauth_apps_owner = create :organization, login: GitHub.trusted_oauth_apps_org_name

      GitHub::CurrentTenant.set(business)

      assert_equal trusted_oauth_apps_owner, Organization.find(trusted_oauth_apps_owner.id)
    end
  end

  test "disallow negative or non-integer business_id" do
    user1 = create_user(business_id: -1)
    refute user1.valid?

    user2 = create_user(business_id: 1.1)
    refute user2.valid?
  end

  test "disallow update to business_id" do
    user = create_user(business_id: 1)
    user.update(business_id: 2)
    user.save
    refute user.valid?
    assert_equal "Business cannot be changed", user.errors.full_messages.to_sentence
  end

  test "create_with_random_password creates user with business_id" do
    opts = {
      "email" => "test@business.com",
      "business_id" => @business.id }
    user = User.create_with_random_password("test@business.com", false, opts)

    assert_predicate user, :valid?
    assert_empty user.errors[:login]
    assert_empty user.errors.full_messages
    assert_equal "test", user.login
    assert_equal @business.id, user.business_id
  end

  test "User.create new must contain a shortcode" do
    user = User.create_with_random_password("mona_lisa@business.com", false, { "email" => "mona_lisa@business.com", "force_enterprise_managed" => true })
    # Creates an invalid user
    # User login must be followed by business suffix but no suffix is supplied
    refute_predicate user, :valid?
    assert_equal user.errors[:login][0], User::LOGIN_VALIDATION_MESSAGE_FOR_EMUS

    user = User.create_with_random_password("mona_lisa@business.com", false, { "email" => "mona_lisa@business.com", "force_enterprise_managed" => true, "login_suffix" => @business.shortcode   })
    assert_predicate user, :valid?
  end

  context "#login_for_api" do
    test "return login for multi tenant internal calls" do
      GitHub.stubs(:proxima_internal_api_unique_logins_required?).returns(true)
      user = create :emu
      refute_equal user.login, user.display_login
      assert_equal user.login, user.login_for_api
    end

    test "returns display_login for multi tenant non-internal calls" do
      user = create :emu
      refute_equal user.login, user.display_login
      assert_equal user.display_login, user.login_for_api
    end

    test "returns login for non multi tenant environments" do
      GitHub.stubs(:multi_tenant_enterprise?).returns(false)
      user = create :emu
      assert_equal user.login, user.display_login
      assert_equal user.login, user.login_for_api
    end

    test "returns unique login when use: is :unique" do
      user = create :emu
      refute_equal user.login, user.display_login
      assert_equal user.display_login, user.login_for_api
      assert_equal user.login, user.login_for_api(use: :unique)
    end

    test "returns display login when use: is :display" do
      user = create :emu
      refute_equal user.login, user.display_login
      assert_equal user.display_login, user.login_for_api
      assert_equal user.display_login, user.login_for_api(use: :display)
    end

    test "returns login for mannequins in each case" do
      user = create(:user)
      business = create(:business)
      org = create(:organization, admin: user, business: business)
      quin = create(:mannequin, :with_profile)

      refute_equal quin.login, quin.display_login
      assert_equal quin.display_login, quin.source_login
      assert_equal quin.login, quin.login_for_api
      assert_equal quin.login.length, 39
    end

  end

  context "instrument_tenant_query_scoping" do
    test "no additional telemetry by default" do
      GitHub.flipper[:tenant_context_telemetry_query_scoping_metrics].disable
      GitHub.flipper[:tenant_context_telemetry_query_scoping_logging].disable

      user = create(:emu, login: "mtodd")
      business = user.enterprise_managed_business

      assert_nil GitHub::CurrentTenant.get
      refute_predicate GitHub::CurrentTenant, :unscoped?

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      Failbot.reports.clear

      assert_nil User.find_by_login("mtodd")

      assert_empty GitHub.dogstats.increments("tenant_context.query_scoping")
      assert_empty Failbot.reports
    end

    test "emits metrics when query scoping with null tenant when tenant_context_telemetry_query_scoping_metrics is enabled" do
      GitHub.flipper[:tenant_context_telemetry_query_scoping_metrics].enable
      GitHub.flipper[:tenant_context_telemetry_query_scoping_logging].disable

      user = create(:emu, login: "mtodd")
      business = user.enterprise_managed_business

      assert_nil GitHub::CurrentTenant.get
      refute_predicate GitHub::CurrentTenant, :unscoped?

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      Failbot.reports.clear

      assert_nil User.find_by_login("mtodd")

      tags = [
        "tenant_set:false",
        "query_scoping:enabled",
      ]
      assert_dogstats_increment 1, "tenant_context.query_scoping", tags: tags
      assert_empty Failbot.reports
    end

    test "emits logging when query scoping with null tenant when tenant_context_telemetry_query_scoping_logging is enabled" do
      GitHub.flipper[:tenant_context_telemetry_query_scoping_metrics].disable
      GitHub.flipper[:tenant_context_telemetry_query_scoping_logging].disable

      user = create(:emu, login: "mtodd")
      business = user.enterprise_managed_business

      assert_nil GitHub::CurrentTenant.get
      refute_predicate GitHub::CurrentTenant, :unscoped?

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      Failbot.reports.clear
      assert_empty Failbot.reports

      GitHub.flipper[:tenant_context_telemetry_query_scoping_logging].enable

      assert_nil User.find_by_login("mtodd")

      assert_empty GitHub.dogstats.increments("tenant_context.query_scoping")
      refute_empty Failbot.reports
      report = Failbot.reports.last
      assert_equal(
        "User::MultiTenantEnterpriseManagedDependency::NullTenantQueryScopingError",
        report.dig("exception_detail", 0, "type")
      )

      # Being redacted here means that keys move from the main hash to `sensitive_context`:
      assert_equal "nil", report.dig("gh.tenant.id")
      assert_equal "false", report.dig("gh.tenant_set")
      assert_equal "enabled", report.dig("gh.tenant.query_scoping")
      assert_nil report.dig("sensitive_context", "gh.tenant.id"), "gh.tenant.id should appear in Failbot report"
      assert_nil report.dig("sensitive_context", "gh.tenant_set"), "gh.tenant_set should appear in Failbot report"
      assert_nil report.dig("sensitive_context", "gh.tenant.query_scoping"), "gh.tenant.query_scoping should appear in the Failbot report"

      assert report.dig("sensitive_context").has_key?("gh.tenant.slug"), "gh.tenant.slug should be filtered to sensitive_data context"
      assert_nil report.dig("gh.tenant.slug"), "gh.tenant.slug should not be used in the Failbot report"
    end
  end

  context "#tenant_slug_for_avatar" do
    test "always returns an empty string when not in multi tenant", skip_in_multitenant_mode: true do
      GitHub.stubs(:multi_tenant_enterprise?).returns(false)
      user = create(:emu)
      assert_equal "", user.tenant_slug_for_avatar
    end

    test "returns company specific entity if `enterprise_managed_business` is nil" do
      on_multi_tenant_enterprise do
        ghost_user = User.ghost
        assert_equal GitHub.company_specific_entity_acronym, ghost_user.tenant_slug_for_avatar
      end
    end

    test "return business slug if user belongs to tenant" do
      on_multi_tenant_enterprise do
        user = create(:emu)
        assert_equal user.enterprise_managed_business.slug, user.tenant_slug_for_avatar
      end
    end
  end
end unless GitHub.enterprise?
