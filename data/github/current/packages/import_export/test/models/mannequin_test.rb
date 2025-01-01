# typed: true
# frozen_string_literal: true

require "test_helper"

class MannequinTest < GitHub::TestCase
  include HydroTestHelpers

  def mannequin
    @mannequin ||= create(:mannequin, owner: @business_organization)
  end

  fixtures do
    @user = create(:user)
    @business = create(:business)
    @business_organization = create(:organization, admin: @user, business: @business)
    @mannequin = create(:mannequin, owner: @business_organization)
  end

  test "has a valid factory" do
    assert_valid @mannequin
  end

  test "requires a login" do
    @mannequin.login = nil
    refute_valid @mannequin
  end

  test "requires a source_login" do
    @mannequin.source_login = nil
    refute_valid @mannequin
  end

  test "display_login_legacy returns source_login" do
    assert_equal @mannequin.source_login, @mannequin.display_login_legacy
  end

  test "display_login returns display_login_legacy" do
    quin = create(:mannequin, :with_profile, owner: @business_organization)

    # display_login is returned from services and the db value is ignored for this mannequin
    refute_equal quin.display_login.length, 39
    assert_equal quin.display_login, quin.source_login
    assert_equal quin.login.length, 39
    assert_equal quin.login_for_api, quin.login

  end

  test "requires an owner" do
    @mannequin.owner = nil
    refute_valid @mannequin
  end

  test "cannot be authenticated" do
    GitHub.dogstats.expects(:increment).with("user", tags: ["action:mannequin_login_attempt"])
    refute @mannequin.authenticated_by_password?(@mannequin.password)
  end

  test "is a subclass of User" do
    assert @mannequin.is_a?(User)
  end

  test "is not an organization" do
    refute @mannequin.organization?
  end

  test "is a mannequin" do
    assert @mannequin.mannequin?
  end

  test "is not a bot" do
    refute @mannequin.bot?
  end

  test "is not a user" do
    refute @mannequin.user?
  end

  test "does not require an email" do
    refute @mannequin.email_address_required?
  end

  test "does not need to verify email" do
    refute @mannequin.must_verify_email?
  end

  test "is valid with a blank email" do
    mannequin = build(:mannequin, email: nil)
    assert !mannequin.email && mannequin.valid?
  end

  test "email is a MannequinEmail" do
    assert @mannequin.emails.first.is_a? MannequinEmail
  end

  test "adds a MannequinEmail" do
    assert_difference "MannequinEmail.count", 1 do
      @mannequin.add_email "foo@bar.com"
    end
  end

  test "has a stealth email" do
    mannequin = build(:mannequin, email: nil)
    stealth_email = StealthEmail.new(mannequin)

    assert_equal mannequin.anonymous_user_email, stealth_email.email
  end

  test "has expected email setter and getter" do
    email = "user@example.com"
    @mannequin.email = email

    assert_equal @mannequin.email, email
  end

  test "can have the same email as a User" do
    mannequin = build(:mannequin, email: @user.email)

    assert mannequin.save
  end

  test "can be destroyed without trying to send confirmation" do
    mannequin = create(:mannequin)

    assert_nothing_raised do
      mannequin.destroy
    end
  end

  test "#never_spammy? returns true" do
    assert @mannequin.never_spammy?
  end

  test "creates a mannequin owner" do
    assert_equal @mannequin.mannequin_ownership.owner, @business_organization
  end

  test "has a claimant" do
    @mannequin.claimant = @user
    assert_equal @mannequin.claimant, @user
  end

  context "in a multi-tenant environment" do
    test "persists business_id" do
      GitHub.stubs(:multi_tenant_enterprise?).returns(true)

      mannequin = create(:mannequin, owner: @business_organization)

      assert_equal(mannequin.business_id, @business.id)
    end

    test "is invalid without a business_id" do
      GitHub.stubs(:multi_tenant_enterprise?).returns(true)

      @business_organization.business = nil
      mannequin = build(:mannequin, owner: @business_organization)

      refute_valid(mannequin)
    end

    test "should not append shortcode to login" do
      GitHub.stubs(:multi_tenant_enterprise?).returns(true)
      User.stubs(:scope_to_current_tenant?).returns(true)
      User.stubs(:tenant_namespacing_enabled?).returns(true)
      Business.any_instance.stubs(:shortcode).returns("foo")

      GitHub::CurrentTenant.set @business

      mannequin = create(:mannequin, owner: @business_organization)
      refute(mannequin.login.include? "_#{@business.shortcode}")
    end

    test "should return login within bounds of LOGIN_MAX_LENGTH" do
      GitHub.stubs(:multi_tenant_enterprise?).returns(true)
      User.stubs(:scope_to_current_tenant?).returns(true)
      User.stubs(:tenant_namespacing_enabled?).returns(true)
      Business.any_instance.stubs(:shortcode).returns("foofoofoofoofoofoofoofoofoofoo")

      GitHub::CurrentTenant.set @business

      mannequin = create(:mannequin, owner: @business_organization)
      assert(mannequin.login.length == User::LOGIN_MAX_LENGTH)
    end

    test "should not append shortcode if not present" do
      User.stubs(:scope_to_current_tenant?).returns(false)
      User.stubs(:tenant_namespacing_enabled?).returns(true)
      Business.any_instance.stubs(:shortcode).returns("foo")

      GitHub::CurrentTenant.set @business

      mannequin = create(:mannequin, owner: @business_organization)
      refute(mannequin.login.include? "_#{@business.shortcode}")
    end
  end

  context "#instrumentation" do
    include HydroTestHelpers

    test "Mannequins should not publish User.signup events to hydro" do
      GitHub.stubs(:hydro_enabled?).returns(true)

      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        create(:mannequin, owner: @business_organization)

        refute_hydro_messages(schema: "github.v1.UserSignup")
      end
    end

    test "Mannequins should not publish User.add_email events to hydro" do
      GitHub.stubs(:hydro_enabled?).returns(true)

      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        @mannequin.add_email("foo@bar.com")

        refute_hydro_messages(schema: "github.v1.UserAddEmail")
      end
    end
  end

  test ".query searches mannequins by source_login" do
    matching_mannequin = create(:mannequin, source_login: "matching")
    non_matching_mannequin = create(:mannequin, source_login: "nope")

    mannequins = Mannequin.query(matching_mannequin.source_login)

    assert_includes mannequins, matching_mannequin
    refute_includes mannequins, non_matching_mannequin
  end

  test ".query searches mannequins by email" do
    matching_mannequin = create(:mannequin)
    non_matching_mannequin = create(:mannequin)

    mannequins = Mannequin.query(matching_mannequin.email)

    assert_includes mannequins, matching_mannequin
    refute_includes mannequins, non_matching_mannequin
  end

  test ".query searches mannequins even without email" do
    matching_mannequin_without_email = create(:mannequin, :with_no_email, source_login: "matching_without_email")
    non_matching_mannequin_without_email = create(:mannequin, :with_no_email, source_login: "nope")

    mannequins = Mannequin.query(matching_mannequin_without_email.source_login)

    assert_includes mannequins, matching_mannequin_without_email
    refute_includes mannequins, non_matching_mannequin_without_email
  end

  test "profile name is scrubbed when updated" do
    mannequin = create(:mannequin)
    mannequin.profile_name = "Valid Name \u{10000}"

    assert mannequin.save!
    assert_equal mannequin.profile_name, "Valid Name"
  end

  test "is not an EMU" do
    mannequin.login = "test_ing"

    refute mannequin.is_enterprise_managed?
  end

  test "is not an EMU when enterprise", enterprise_only: true do
    mannequin.login = "test_ing"

    refute mannequin.is_enterprise_managed?
  end

  test "is not an EMU when single_tenant_enterprise" do
    GitHub.stubs(:single_tenant_enterprise?).returns(true)
    mannequin.login = "test_ing"

    refute mannequin.is_enterprise_managed?
  end

  test "is not an EMU when multi_tenant_enterprise" do
    GitHub.stubs(:multi_tenant_enterprise?).returns(true)
    mannequin.login = "test_ing"

    refute mannequin.is_enterprise_managed?
  end
end
