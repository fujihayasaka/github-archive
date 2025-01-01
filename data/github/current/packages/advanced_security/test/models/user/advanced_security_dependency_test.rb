# typed: true
# frozen_string_literal: true

require "test_helper"

class UserAdvancedSecurityDependencyTest < GitHub::TestCase
  include TurboghasHelpers

  fixtures do
    today = Time.zone.today
    @owner = create(:user)

    if GitHub.enterprise?
      GitHub::Enterprise.ensure_business!
      @business = GitHub.global_business
    else
      @business = create :business, owners: [@owner]
      @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
    end

    @orgs = (0...4).map { |_i| create :organization, admin: @owner, business: @business }

    repos = T.let([], T::Array[Repository])
    (0...30).each do |i|
      # Most repos are owned by @orgs[3] so we can see if unique committer
      # calculations correctly include this org when they should be.
      owner = i < 4 ? @orgs[i] : @orgs[3]
      # We deliberately name them in reverse to highlight the sort order, and
      # every other repo is private because they should be counted on GHES but
      # not on dotcom.
      repo = create(:repository, name: "repo%02i" % (30 - i), owner: owner, private: i % 2 == 0)
      if GitHub.enterprise? || repo.private?
        repo.enable_advanced_security!(actor: @owner)
      end
      repos << repo
    end
    repo = create(:repository, name: "user-owned-repo", owner: @owner)
    repos << repo

    (2...12).each_with_index do |p, i|
      contributor = create :user, disabled: i == 7, suspended_at: i == 8 ? Time.current : nil
      date = i == 9 ? today - 91.days : today
      repos.each_with_index do |repo, j|
        if j % p == 0
          next unless repo.owner&.organization?

          T.cast(repo.owner, Organization).add_member(contributor)
        end
      end
    end
    # "repo20" gets an extra committer from a user that does't commit elsewhere
    # to test the unique case.
    unique_user = create :user
    tenth_repo = repos[10]
    T.cast(tenth_repo.owner, Organization).add_member(unique_user) if tenth_repo
  end

  setup do
    # We re-initialize the objects because the license is cached.
    @owner = User.find(@owner.id)
    (0...4).each do |i|
      @orgs[i] = User.find(@orgs[i].id)
    end

    GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true) if GitHub.enterprise?
  end

  test "turboghas is wired-in correctly", skip_enterprise: true do
    VCR.use_cassette("get-repositories", persist_with: :turboghas) do
      data = @orgs[3].get_advanced_security_repos_and_counts(page: 0, page_size: 10)
      assert_same_elements [:repos, :total_repos_count, :num_repos_without_ghas], data.keys
      assert_equal 2, data[:repos].size
      assert_same_elements [:id, :name, :committer_count, :unique_committer_count], data[:repos].first.keys
    end
  end

  test "org with no license returns no results", enterprise_only: true do
    GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)

    want = { repos: [], total_repos_count: 0 }
    got = @orgs[0].get_advanced_security_repos_and_counts(page: 0, page_size: 10)
    assert_equal want, got
  end

  # Some single sanity checks of seat_usage_increase_if_advanced_security_enabled_for_all_repos
  # but not particularly in-depth tests because that method is entirely built upon existing components
  # that are themselves well tested.
  context "#seat_usage_increase_if_advanced_security_enabled_for_all_repos" do
    test "empty org" do
      org = create(:organization, admin: @owner, business: @business)

      assert_equal 0, org.seat_usage_increase_if_advanced_security_enabled_for_all_repos
    end
  end

  context "#enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?" do
    test "returns false if GHAS not purchased" do
      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
      else
        @business.mark_advanced_security_as_not_purchased_for_entity(actor: @owner)
      end

      # Set these so it would return true if GHAS were enabled
      AdvancedSecurityLicense.any_instance.stubs(:seats).returns(10)
      AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(15)

      refute @orgs[0].enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end

    test "returns false if GHAS license has unlimited seats" do
      AdvancedSecurityLicense.any_instance.stubs(:seats).returns(0)
      AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(5)
      Organization.any_instance.stubs(:seat_usage_increase_if_advanced_security_enabled_for_all_repos).returns(20)

      refute @orgs[0].enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end

    test "returns true if GHAS license already exceeded" do
      AdvancedSecurityLicense.any_instance.stubs(:seats).returns(10)
      AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(15)
      Organization.any_instance.stubs(:seat_usage_increase_if_advanced_security_enabled_for_all_repos).returns(0)

      assert @orgs[0].enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end

    test "returns true if GHAS license is not currently exceeded but would be exceeded" do
      AdvancedSecurityLicense.any_instance.stubs(:seats).returns(10)
      AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(5)
      Organization.any_instance.stubs(:seat_usage_increase_if_advanced_security_enabled_for_all_repos).returns(20)

      assert @orgs[0].enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end

    test "returns false if GHAS license is not currently exceeded and would not be exceeded" do
      AdvancedSecurityLicense.any_instance.stubs(:seats).returns(10)
      AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(5)
      Organization.any_instance.stubs(:seat_usage_increase_if_advanced_security_enabled_for_all_repos).returns(3)

      refute @orgs[0].enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end

    test "returns false if GHAS license is at limit but enabling would not use more seats" do
      AdvancedSecurityLicense.any_instance.stubs(:seats).returns(10)
      AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(10)
      Organization.any_instance.stubs(:seat_usage_increase_if_advanced_security_enabled_for_all_repos).returns(0)

      refute @orgs[0].enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end
  end

  context "advanced_security_configurable?" do
    test "disabled for org with GHAS not purchased" do
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false) if GitHub.enterprise?
      org = create(:organization, admin: @owner)
      refute org.advanced_security_configurable?
    end

    test "enabled for org on dotcom with GHAS purchased", skip_enterprise: true do
      org = create(:organization, admin: @owner)
      org.business = create :business
      org.business.mark_advanced_security_as_purchased_for_entity(actor: @owner)

      assert org.advanced_security_configurable?
    end

    test "enabled for org on GHES with GHAS purchased", enterprise_only: true do
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      org = create(:organization, admin: @owner)
      assert org.advanced_security_configurable?
    end

    test "enabled for one org but not other org on dotcom", skip_enterprise: true do
      org = create(:organization, admin: @owner)
      org.mark_advanced_security_as_purchased_for_entity(actor: @owner)
      org2 = create(:organization, admin: @owner)

      assert org.advanced_security_configurable?
      refute org2.advanced_security_configurable?
    end
  end
end

class UserAdvancedSecurityDependencyEMUTest < Api::TestCase
  fixtures do
    @owner = create(:user)

    if GitHub.enterprise?
      @business = create(:global_business)
      @user = create(:user)
    else
      @business = create(:business, :enterprise_managed)
      @emu_user = create(:emu, business: @business)
      @emu_owned_repo = create(:private_repository, force_user_owned: true, owner: @emu_user)
    end
    @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
  end

  context "advanced_security_configurable?" do
    test "enabled for EMU when feature flag enabled", skip_enterprise: true do
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
      assert @emu_user.advanced_security_configurable?
    end

    test "disabled for user when feature flag disabled", enterprise_only: true do
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false)
      refute @user.advanced_security_configurable?
    end

    test "disabled for non-EMU when feature flag enabled", skip_enterprise: true do
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
      refute create(:user).advanced_security_configurable?
    end

    test "enabled for user on GHES when feature flag enabled", enterprise_only: true do
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
      assert @owner.advanced_security_configurable?
    end

    test "disabled for user on GHES when feature flag disabled", enterprise_only: true do
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false)
      refute @owner.advanced_security_configurable?
    end
  end
end
