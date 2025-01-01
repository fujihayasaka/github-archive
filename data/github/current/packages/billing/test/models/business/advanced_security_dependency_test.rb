# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessAdvancedSecurityDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    if GitHub.enterprise?
      GitHub::Enterprise.ensure_business!
      @business = GitHub.global_business
    else
      create(:billing_product_uuid, :advanced_security)
      @business = create(:business, owners: [@user])
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
    end

    # This user contributes to all repos, but isn't a member of any of the orgs
    # and so shouldn't be counted in any of the totals for dotcom.
    @unrelated_user = create :user
  end

  setup do
    @today = Time.zone.today
    GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true) if GitHub.enterprise?
  end

  # Set things up so that enabling_advanced_security_would_exceed_seat_allowance? would return true.
  # This will be a shared starting point for each test of this method.
  def setup_for_enabling_advanced_security_would_exceed_seat_allowance
    if GitHub.enterprise?
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)
    else
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @business.set_advanced_security_seats_for_entity(seats: 10, actor: @user)
    end

    @business.advanced_security_license.stubs(:consumed_seats).returns(7)
    @business.stubs(:seat_usage_increase_if_advanced_security_enabled_for_all_repos).returns(5)
  end

  def setup_self_serve_business_for_enabling_advanced_security_would_exceed_seat_allowance
    return if GitHub.enterprise?
    @business = create(:business, :with_self_serve_payment, owners: [@user])
    @business.subscribe_to_advanced_security(seats: 10, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

    @business.advanced_security_license.stubs(:consumed_seats).returns(7)
    @business.stubs(:seat_usage_increase_if_advanced_security_enabled_for_all_repos).returns(5)
  end

  context "#enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?" do
    test "Returns false if GHAS not purchased" do
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
      else
        @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
      end

      refute @business.enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end

    test "Returns false if unlimited license" do
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(0)
      else
        @business.set_advanced_security_seats_for_entity(seats: 0, actor: @user)
      end

      refute @business.enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end

    test "Returns false if seat limit would not be exceeded" do
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      @business.stubs(:seat_usage_increase_if_advanced_security_enabled_for_all_repos).returns(2)

      refute @business.enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end

    test "Returns false if consumed seats is at the limit but the new repo uses no extra seats" do
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      @business.advanced_security_license.stubs(:consumed_seats).returns(10)
      @business.stubs(:seat_usage_increase_if_advanced_security_enabled_for_all_repos).returns(0)

      refute @business.enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end

    test "Returns true if seat limit would be exceeded" do
      # Deliberately do no other changes beyond what's in the following method.
      # This ensures the changes made in the other tests are doing what we expect
      # and we're not getting spurious test passes.
      setup_for_enabling_advanced_security_would_exceed_seat_allowance
      @business.advanced_security_license.stubs(:seats).returns(10)

      assert @business.enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end

    test "Returns true if seat limit already exceeded" do
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      @business.advanced_security_license.stubs(:consumed_seats).returns(15)
      @business.stubs(:seat_usage_increase_if_advanced_security_enabled_for_all_repos).returns(0)
      @business.advanced_security_license.stubs(:seats).returns(10)

      assert @business.enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end
  end

  context "advanced_security_configurable?" do
    test "disabled for businesses with GHAS not purchased" do
      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
      else
        @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
      end
      refute @business.advanced_security_configurable?
    end

    test "enabled for business repo on dotcom with GHAS purchased", skip_enterprise: true do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      assert @business.advanced_security_configurable?
    end
  end

  test "get_advanced_security_orgs_and_counts" do
    org2 = create(:organization, name: "org-b", business: @business)
    org1 = create(:organization, name: "org-a", business: @business)
    create(:organization, name: "org-c", business: @business)

    @business.set_advanced_security_seats_for_entity(actor: @user, seats: 0)

    VCR.use_cassette("get-organizations", persist_with: :turboghas) do |cassette|
      T.cast(cassette.http_interactions, VCR::Cassette::HTTPInteractionList).interactions.each do |interaction|
        body = JSON.parse(interaction.response.body)
        body["organizations"][0]["id"] = org1.id
        body["organizations"][1]["id"] = org2.id
        interaction.response.body = JSON.dump(body)
      end

      res = @business.get_advanced_security_orgs_and_counts(page: 0)
      assert_equal 2, res[:orgs].size
      assert_equal 2, res[:total_orgs_count]
      assert_equal 1, res[:num_orgs_without_ghas]

      assert_equal org1.id, res[:orgs][0][:organization].id
      assert_equal 2, res[:orgs][0][:committer_count]
      assert_equal 1, res[:orgs][0][:unique_committer_count]

      assert_equal org2.id, res[:orgs][1][:organization].id
      assert_equal 1, res[:orgs][1][:committer_count]
      assert_equal 0, res[:orgs][1][:unique_committer_count]
    end
  end
end

class ManagedBusinessAdvancedSecurityDependencyTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @business = create(:business, :enterprise_managed)
    @owner = @business.owners.first
    # matches cassette
    # must be created with `id`, so that we can lookup the user from the cassette
    User.where(id: [6]).delete_all
    @emu = create(:emu, business: @business, id: 6, login: "emu-6-billable")

    non_emus = 5.times.map { create(:user).id }
  end

  setup do
    if GitHub.enterprise?
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)
    else
      @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
      @business.set_advanced_security_seats_for_entity(actor: @owner, seats: 10)
    end
  end

  context "#get_advanced_security_users_and_counts" do
    test "fetches from turboghas" do
      VCR.use_cassette("get-enterprise-users", persist_with: :turboghas) do
        assert @emu.is_enterprise_managed?
        res = @business.get_advanced_security_enterprise_users_and_counts(actor: @owner, page: 1)
        assert_equal 1, res[:users].size
        assert_equal 1, res[:count]

        assert_equal @emu.id, res[:users][0][:user].id
        assert_equal 1, res[:users][0][:committer_count]
        assert_equal 1, res[:users][0][:unique_committer_count]
      end
    end
  end
end
