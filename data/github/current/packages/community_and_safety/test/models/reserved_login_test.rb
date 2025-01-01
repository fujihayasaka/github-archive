# typed: true
# frozen_string_literal: true

require "test_helper"

class ReservedLoginTest < GitHub::TestCase
  fixtures do
    @reserved_login = create :reserved_login
    @staff = create :staff_admin_user
    @user = create :user
    @harcoded_reserved_login = ReservedLogin.create login: "about"

    if TestEnv.test_with_all_emus?
      @emu = create(:emu)
      @shortcode = @emu.enterprise_managed_business.shortcode
    end
  end

  def enable_multi_tenant_namespacing
    if TestEnv.test_with_all_emus?
      current_tenant = @emu.enterprise_managed_business
      GitHub::CurrentTenant.set(current_tenant)

      yield

      GitHub::CurrentTenant.remove
    end
  end

  test "validates login" do
    login = "rand:om.chars"
    bl = ReservedLogin.create(login: login)
    assert_equal ["Login is invalid"], bl.errors.full_messages
  end

  # Skipping this test in enterprise for now, see:
  # https://github.com/github/ghes/issues/9918
  test "checks username denylist is up to date", skip_enterprise: true do
    violations = []
    routes = Rails.application.routes.routes.each do |route|
      path_name = route.path.spec.to_s
      next unless path_name.match(/\A\/[^\/]+\Z/)
      next unless route.verb.include? "GET"

      username = path_name.delete_prefix("/").delete_suffix("(.:format)")
      next unless User::LOGIN_REGEX.match?(username)
      next if GitHub::DeniedLogins.include? username.downcase
      violations << username
    end

    assert violations.empty?, "The following routes are not in GitHub::DeniedLogins: #{violations.join(", ")}"
  end

  test "downcases login" do
    bl = ReservedLogin.create! login: "RESERVED"
    assert_equal "reserved", bl.login
  end

  test "enforces unique logins" do
    bl = ReservedLogin.create login: @reserved_login.login
    assert ReservedLogin.reserved?(@reserved_login.login)
    bl2 = ReservedLogin.create login: @reserved_login.login
    assert_equal ["Login has already been reserved"], bl2.errors.full_messages
  end

  test "requires the login" do
    bl = ReservedLogin.create
    refute_predicate bl, :valid?
    assert_equal ["Login can't be blank", "Login is invalid"], bl.errors.full_messages
  end

  test "knows if a reserved login is hardcoded" do
    refute_predicate @reserved_login, :hardcoded?
    assert_predicate @harcoded_reserved_login, :hardcoded?
  end

  context "#instrument_create" do
    # We want these instrumented because they correspond to staff actions in the
    # stafftools UI.
    test "creates audit log events for manually-created staff-reserved logins" do
      events = subscribe("reserved_login.create")
      reserved = create :reserved_login
      assert_equal events.size, 1
      assert_equal events[0].payload, { login: reserved.login, reason: nil }
    end

    # We don't want these instrumented because they happen automatically as
    # a side-effect of user deletion, and the records are not listed in the
    # stafftools UI.
    test "does not create audit log events for automatically-generated tombstone records" do
      events = subscribe("reserved_login.create")
      reserved = create :reserved_login, :tombstoned
      assert_equal events.size, 0
    end
  end

  context "#instrument_destroy" do
    # We want these instrumented because they correspond to staff actions in the
    # stafftools UI. Even though we don't list tombstone records in the default
    # list view, it is possible to explicitly search for and destroy a
    # tombstone, so that should be reflected in the audit log.
    test "creates audit log events for all kinds of records" do
      reserved = create :reserved_login
      tombstoned = create :reserved_login, :tombstoned

      events = subscribe("reserved_login.destroy")
      reserved.destroy!
      tombstoned.destroy!

      assert_equal events.size, 2
      assert_equal events[0].payload, { login: reserved.login }
      assert_equal events[1].payload, { login: tombstoned.login }
    end

    # We don't want these instrumented because they happen automatically as a
    # side-effect of the DeleteExpiredReservedLoginTombstonesJob.
    test "does nothing during bulk updates" do
      create :reserved_login, :tombstoned, expires_at: 5.minutes.ago
      events = subscribe("reserved_login.destroy")
      ReservedLogin.delete_expired_tombstones
      assert_equal events.size, 0
    end
  end

  context "#kind" do
    test "defaults to staff_reserved" do
      login = create :reserved_login
      assert_equal login.kind, "staff_reserved"
    end
  end

  context "#staff_reserved?" do
    test "returns true for staff-reserved logins" do
      login = create :reserved_login
      assert_predicate login, :staff_reserved?

      login = create :reserved_login, :tombstoned
      refute_predicate login, :staff_reserved?
    end
  end

  context "#tombstoned?" do
    test "returns true for tombstoned logins" do
      login = create :reserved_login, :tombstoned
      assert_predicate login, :tombstoned?

      login = create :reserved_login
      refute_predicate login, :tombstoned?
    end
  end

  context "#tombstone_expired?" do
    test "returns false for staff-reserved logins" do
      login = create :reserved_login
      refute_predicate login, :tombstone_expired?
    end

    test "returns false for tombstoned logins without expiry dates" do
      login = create :reserved_login, :tombstoned, expires_at: nil
      refute_predicate login, :tombstone_expired?
    end

    test "returns false for tombstoned logins with expiry dates in the future" do
      login = create :reserved_login, :tombstoned, expires_at: 1.week.from_now
      refute_predicate login, :tombstone_expired?
    end

    test "returns true for tombstoned logins that have expired already" do
      login = create :reserved_login, :tombstoned, expires_at: 2.months.ago
      assert_predicate login, :tombstone_expired?
    end
  end

  context "class methods" do
    test "knows hardcoded logins are reserved" do
      assert ReservedLogin.reserved? "support"
    end

    test "knows hardcoded logins are hardcoded" do
      assert ReservedLogin.hardcoded? "support"
    end

    test "knows reserved logins aren't hardcoded" do
      refute ReservedLogin.hardcoded? @reserved_login.login
    end

    test "knows reserved logins are reserved" do
      assert ReservedLogin.reserved? @reserved_login.login
    end

    test "knows other logins aren't reserved" do
      refute ReservedLogin.reserved? @user.login
    end

    test "knows other logins aren't hardcoded" do
      refute ReservedLogin.hardcoded? @user.login
    end

    test "does not fail on logins containing emoji characters" do
      refute ReservedLogin.reserved? "🔥"
    end

    test "find a reserved login" do
      login = @reserved_login.login.upcase
      assert_equal @reserved_login, ReservedLogin.find_by(login: login.downcase)
    end

    context "enterprise", enterprise_only: true do
      test "it does not consider tombstoned logins to be reserved" do
        tombstone = create :reserved_login, :tombstoned, expires_at: 1.week.from_now
        refute ReservedLogin.reserved?(tombstone.login)
        tombstone = create :reserved_login, :tombstoned, expires_at: nil
        refute ReservedLogin.reserved?(tombstone.login)
      end
    end

    context "dotcom", skip_enterprise: true do
      test "it considers unexpired tombstoned logins to be reserved" do
        tombstone = create :reserved_login, :tombstoned, expires_at: 1.week.from_now
        assert ReservedLogin.reserved?(tombstone.login)
        tombstone = create :reserved_login, :tombstoned, expires_at: nil
        assert ReservedLogin.reserved?(tombstone.login)
      end

      test "it considers expired tombstoned logins not to be reserved" do
        tombstone = create :reserved_login, :tombstoned, expires_at: 2.days.ago
        refute ReservedLogin.reserved?(tombstone.login)
      end
    end

    context ".reserve!" do
      test "creates a staff-reserved login" do
        record = ReservedLogin.reserve!("prohibited")
        assert_predicate record, :valid?
        assert_predicate record, :staff_reserved?
      end

      test "raises an error if the login is invalid" do
        assert_raises ActiveRecord::RecordInvalid do
          ReservedLogin.reserve!("---")
        end
      end
    end

    context ".tombstone!" do
      context "enterprise", enterprise_only: true do
        test "does nothing" do
          assert_nil ReservedLogin.tombstone!("foo")
        end
      end

      context "dotcom", skip_enterprise: true do
        test "creates a tombstoned login" do
          record = ReservedLogin.tombstone!("foo")
          assert_predicate record, :valid?
          assert_predicate record, :tombstoned?
        end

        test "sets an expiry date 90 days in the future" do
          record = ReservedLogin.tombstone!("bar")
          assert_in_delta record.expires_at, 90.days.from_now, 5.seconds
        end

        test "raises an error if the login is invalid" do
          assert_raises ActiveRecord::RecordInvalid do
            ReservedLogin.tombstone!("---")
          end
        end
      end
    end

    context ".tombstoned scope" do
      test "returns tombstoned records" do
        expired = create :reserved_login, :tombstoned, expires_at: 1.day.ago
        unexpired = create :reserved_login, :tombstoned, expires_at: 10.weeks.ago
        permanent = create :reserved_login, :tombstoned, expires_at: nil
        not_a_tombstone = create :reserved_login

        assert_equal ReservedLogin.tombstoned.order("id ASC"), [expired, unexpired, permanent]
      end
    end

    context ".untombstone!" do
      test "removes a tombstone record if it exists" do
        tombstoned = create :reserved_login, :tombstoned
        ReservedLogin.untombstone!(tombstoned.login)
        assert_nil ReservedLogin.find_by(id: tombstoned.id)
      end

      test "does not remove a staff-reserved login if it exists" do
        reserved = create :reserved_login
        ReservedLogin.untombstone!(reserved.login)
        assert_equal reserved, ReservedLogin.find(reserved.id)
      end

      test "does nothing if no record exists" do
        user = build :user
        assert_nil ReservedLogin.untombstone!(user.login)
      end
    end

    context ".delete_expired_tombstones" do
      test "deletes expired tombstones" do
        expired = create :reserved_login, :tombstoned, expires_at: 1.day.ago
        unexpired = create :reserved_login, :tombstoned, expires_at: 10.weeks.from_now
        permanent = create :reserved_login, :tombstoned, expires_at: nil
        not_a_tombstone = create :reserved_login

        ReservedLogin.delete_expired_tombstones

        refute ReservedLogin.exists?(login: expired.login)
        assert ReservedLogin.exists?(login: unexpired.login)
        assert ReservedLogin.exists?(login: permanent.login)
        assert ReservedLogin.exists?(login: not_a_tombstone.login)
      end
    end
  end

  context "multi-tenant" do
    # In Proxima, reserved logins will apply for ALL tenants on a stamp (or globally)
    # and therefore we should compare the reserved login to the unsuffixed, display_login
    test "compares the display_login to a stored reserved login" do
      enable_multi_tenant_namespacing do
        reserved = create(:reserved_login, login: "proxima")
        assert ReservedLogin.reserved?("proxima")
        assert ReservedLogin.reserved?("proxima_#{@shortcode}")
      end
    end

    test "compares display_login to a hardcoded reserved login" do
      enable_multi_tenant_namespacing do
        reserved = GitHub::DeniedLogins.first
        assert ReservedLogin.reserved?(reserved)
        assert ReservedLogin.reserved?("#{reserved}_#{@shortcode}")
      end
    end

    test "does not consider tombstoned logins to be reserved" do
      enable_multi_tenant_namespacing do
        tombstoned = create :reserved_login, :tombstoned
        refute ReservedLogin.reserved?(tombstoned.login)
      end
    end
  end

  context "restricted keywords" do
    test "does not allow reserved logins to be created with restricted keywords as part of the login on dotcom", skip_enterprise: true, skip_in_multitenant_mode: true do
      Rails.env.stubs(:test?).returns(false)

      assert ReservedLogin.reserved?("sdfsdgithubsdfsd", skip_keyword_check: false)
      assert ReservedLogin.reserved?("githubsdfsd", skip_keyword_check: false)
      assert ReservedLogin.reserved?("sdfsdgithub", skip_keyword_check: false)
      assert ReservedLogin.reserved?("dependabotsdfsd", skip_keyword_check: false)
    end

    test "allow reserved logins to be created with restricted keywords from allowed logins list on dotcom", skip_enterprise: true, skip_in_multitenant_mode: true do
      Rails.env.stubs(:test?).returns(false)
      GitHub::AllowedLogins << "sdfsdgithubsdfsd"

      refute ReservedLogin.reserved?("sdfsdgithubsdfsd", skip_keyword_check: false)

      GitHub::AllowedLogins.delete("sdfsdgithubsdfsd")
    end

    test "can't create a user with a login that contains a restricted login keyword in dotcom", skip_enterprise: true, skip_in_multitenant_mode: true do
      Rails.env.stubs(:test?).returns(false)

      reserved_keyword_login = "github-user"
      user = build(:user, login: reserved_keyword_login)
      user.valid?

      assert_equal :restricted_login_keyword, user.errors.where(:login).first.type
      assert_equal "Username '#{reserved_keyword_login}' contains a reserved keyword", user.errors.where(:login).first.full_message
    end

    test "can update an existing user with a login with a restricted login keyword when updating a non-login field on dotcom", skip_enterprise: true, skip_in_multitenant_mode: true do
      user = build(:user, login: "dependabot-user")
      user.save!

      Rails.env.stubs(:test?).returns(false)

      user.profile_name = "updated profile name"

      assert user.valid?
    end

    test "can't update an existing user login to a login with a restricted login keyword in dotcom", skip_enterprise: true, skip_in_multitenant_mode: true do
      user = build(:user, login: "a-user")
      user.save!

      Rails.env.stubs(:test?).returns(false)

      reserved_keyword_login = "github-user"
      user.login = reserved_keyword_login
      user.valid?

      assert_equal :restricted_login_keyword, user.errors.where(:login).first.type
      assert_equal "Username '#{reserved_keyword_login}' contains a reserved keyword", user.errors.where(:login).first.full_message
    end

    test "can create a user with a login that contains a restricted login keyword in GHES", enterprise_only: true do
      Rails.env.stubs(:test?).returns(false)

      user = build(:user, login: "github-user")

      assert user.valid?
    end

    test "can create an EMU user with a login that contains a restricted login keyword", skip_enterprise: true do
      Rails.env.stubs(:test?).returns(false)

      user = build(:emu, login: "github-user")

      assert user.valid?
    end

    test "can create an integration with names that contain a restricted login keyword including 'github' and 'dependabot'" do
      Rails.env.stubs(:test?).returns(false)

      # Integrations do their own name checking and the underlying bot would fail validation
      # if the name started with "github" for example, but not when "github" is in the middle
      # of the app name.
      %w[a-github-app a-dependabot-app].each do |name|
        integration = build(:integration, name: name)

        assert integration.valid?
      end
    end
  end
end
