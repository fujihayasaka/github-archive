# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseBannerTest < GitHub::TestCase
  # Tests also exist in enterprise_banner_dismissal_test.rb

  include AuditLog::IntegrationTestHelpers

  fixtures do
    @user = create(:user)
    @user2 = create(:user)
    @org = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org)
    @business = create(:business, owners: [@user], organizations: [@org])
  end

  test "can create valid banners" do
    assert_predicate build(:enterprise_banner, owner: @business, dismissible: true), :valid?
    assert_predicate build(:enterprise_banner, :for_org, dismissible: true), :valid?
    assert_predicate build(:enterprise_banner, :for_repo, dismissible: true), :valid?
  end

  test "can detect invalid banners" do
    refute_predicate build(:enterprise_banner, owner: @business), :valid?
  end

  test "message max length" do
    too_long_msg = ""
    600.times do
      too_long_msg += "a"
    end

    refute_predicate build(:enterprise_banner, owner: @business, message: too_long_msg), :valid?
  end

  # TODO figure out how to properly write this, as i'm not sure how to handle timezones
  # test "expiration date must be at least 1 minute in the future" do
  #   Timecop.freeze do
  #     refute_predicate build(:enterprise_banner, owner: @business, expires_at: Time.now.utc - 1.day), :valid?
  #     refute_predicate build(:enterprise_banner, owner: @business, expires_at: Time.now.utc + 50.seconds), :valid?
  #     assert_predicate build(:enterprise_banner, owner: @business, expires_at: Time.now.utc + 2.minutes), :valid?
  #     assert_predicate build(:enterprise_banner, owner: @business, expires_at: nil), :valid?
  #   end
  # end

  test "deleting banner destroys all dismissals" do
    dismissible_banner = create(:enterprise_banner, owner: @business, dismissible: true)
    assert_equal true, dismissible_banner.dismissible
    dismissible_banner.dismiss(@user)
    dismissible_banner.dismiss(@user2)

    refute_nil EnterpriseBannerDismissal.find_by(enterprise_banner: dismissible_banner, user: @user)
    refute_nil EnterpriseBannerDismissal.find_by(enterprise_banner: dismissible_banner, user: @user2)

    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { dismissible_banner.destroy }
    refute_predicate EnterpriseBanner.where(id: dismissible_banner.id), :exists?

    assert_nil EnterpriseBannerDismissal.find_by(enterprise_banner: dismissible_banner)
  end

  test "instruments create event" do
    events = assert_performed_audit_entries(count: 1, only: "enterprise_announcement.create") do
      EnterpriseBanner.new(owner: @repo, message: "Hello world", dismissible: true).upsert_for(@repo, @user)
    end

    expected_payload = {
      actor: @user.display_login,
      owner: @repo.name_with_display_owner,
      owner_type: "repository",
      business: @business.name,
      business_id: @business.id,
      message: "Hello world",
      dismissibility: true,
      expiry: nil,
      repo: @repo.name_with_display_owner,
      repo_id: @repo.id,
      org: @org.display_login,
      org_id: @org.id,
    }

    assert_subset_hash expected_payload, events.first
  end

  test "instruments update event" do
    create(:enterprise_banner, owner: @business, message: "Hello world", dismissible: true)

    events = assert_performed_audit_entries(count: 1, only: "enterprise_announcement.update") do
      EnterpriseBanner.new(owner: @business, message: "Goodbye world", dismissible: true).upsert_for(@business, @user)
    end

    expected_payload = {
      actor: @user.display_login,
      owner: @business.name,
      owner_type: "enterprise",
      business: @business.name,
      business_id: @business.id,
      old_message: "Hello world",
      message: "Goodbye world",
    }

    assert_subset_hash expected_payload, events.first
    assert_nil expected_payload[:repo_id]
    assert_nil expected_payload[:org_id]
  end

  test "instruments destroy event" do
    banner = create(:enterprise_banner, owner: @org, dismissible: true)

    events = assert_performed_audit_entries(count: 1, only: "enterprise_announcement.destroy") do
      EnterpriseBanner.clear_for(@org, @user)
    end

    expected_payload = {
      actor: @user.display_login,
      owner: @org.display_login,
      owner_type: "organization",
      business: @business.name,
      business_id: @business.id,
      org: @org.display_login,
      org_id: @org.id,
    }

    assert_subset_hash expected_payload, events.first
    assert_nil expected_payload[:repo_id]
  end
end
