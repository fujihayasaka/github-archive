# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadSponsorshipPayloadTest < GitHub::TestCase
  fixtures do
    @action = :created

    @sponsored_user = create(:user)
    create(:sponsors_listing, :approved, sponsorable: @sponsored_user)
    @sponsored_user_hook = create(:hook,
      installation_target: @sponsored_user.sponsors_listing,
      events: %w(sponsorship),
    )

    @sponsored_org = create(:organization, :sponsorable)
    @sponsored_org_hook = create(:hook,
      installation_target: @sponsored_org.sponsors_listing,
      events: %w(sponsorship),
    )
  end

  test "public recurring sponsorship of a user" do
    sponsorship = create(:sponsorship, sponsorable: @sponsored_user)
    sponsor = sponsorship.sponsor
    tier = sponsorship.subscription_item.subscribable
    event = Hook::Event::SponsorshipEvent.new(
      action: @action,
      sponsorship_id: sponsorship.id,
      actor_id: sponsor.id,
      current_tier_id: tier.id,
    )

    payload = Hook::Payload::SponsorshipPayload.new(event)
    v3 = payload.to_hash

    assert_equal @action, v3[:action]
    assert_equal sponsor.login, v3.dig(:sender, :login)
    assert_equal sponsorship.global_relay_id, v3.dig(:sponsorship, :node_id)
    assert_equal @sponsored_user.login, v3.dig(:sponsorship, :sponsorable, :login)
    assert_equal @sponsored_user.login, v3.dig(:sponsorship, :maintainer, :login)
    assert_equal sponsor.login, v3.dig(:sponsorship, :sponsor, :login)
    assert_equal "public", v3.dig(:sponsorship, :privacy_level)
    assert_equal tier.global_relay_id, v3.dig(:sponsorship, :tier, :node_id)
    assert_equal tier.monthly_price_in_cents, v3.dig(:sponsorship, :tier, :monthly_price_in_cents)
    refute v3.dig(:sponsorship, :tier, :is_custom_amount)
    refute v3.dig(:sponsorship, :tier, :is_one_time)
    refute_includes v3.keys, :changes
    refute_includes v3.keys, :effective_date
  end

  test "public one-time sponsorship of a user" do
    tier = create(:sponsors_tier, :published, :one_time,
      sponsors_listing: @sponsored_user.sponsors_listing)
    sponsorship = create(:sponsorship, sponsorable: @sponsored_user, tier: tier)
    sponsor = sponsorship.sponsor
    event = Hook::Event::SponsorshipEvent.new(
      action: @action,
      sponsorship_id: sponsorship.id,
      actor_id: sponsor.id,
      current_tier_id: tier.id,
    )

    payload = Hook::Payload::SponsorshipPayload.new(event)
    v3 = payload.to_hash

    assert_equal @action, v3[:action]
    assert_equal sponsor.login, v3.dig(:sender, :login)
    assert_equal sponsorship.global_relay_id, v3.dig(:sponsorship, :node_id)
    assert_equal @sponsored_user.login, v3.dig(:sponsorship, :sponsorable, :login)
    assert_equal @sponsored_user.login, v3.dig(:sponsorship, :maintainer, :login)
    assert_equal sponsor.login, v3.dig(:sponsorship, :sponsor, :login)
    assert_equal "public", v3.dig(:sponsorship, :privacy_level)
    assert_equal tier.global_relay_id, v3.dig(:sponsorship, :tier, :node_id)
    assert_equal tier.monthly_price_in_cents, v3.dig(:sponsorship, :tier, :monthly_price_in_cents)
    refute v3.dig(:sponsorship, :tier, :is_custom_amount)
    assert v3.dig(:sponsorship, :tier, :is_one_time)
    refute_includes v3.keys, :changes
    refute_includes v3.keys, :effective_date
  end

  test "public sponsorship of a user using a custom amount" do
    tier = create(:sponsors_tier, :custom, sponsors_listing: @sponsored_user.sponsors_listing)
    sponsorship = create(:sponsorship, sponsorable: @sponsored_user, tier: tier,
      sponsor: tier.creator)
    sponsor = sponsorship.sponsor
    event = Hook::Event::SponsorshipEvent.new(
      action: @action,
      sponsorship_id: sponsorship.id,
      actor_id: sponsor.id,
      current_tier_id: tier.id,
    )

    payload = Hook::Payload::SponsorshipPayload.new(event)
    v3 = payload.to_hash

    assert_equal @action, v3[:action]
    assert_equal sponsor.login, v3.dig(:sender, :login)
    assert_equal sponsorship.global_relay_id, v3.dig(:sponsorship, :node_id)
    assert_equal @sponsored_user.login, v3.dig(:sponsorship, :sponsorable, :login)
    assert_equal @sponsored_user.login, v3.dig(:sponsorship, :maintainer, :login)
    assert_equal sponsor.login, v3.dig(:sponsorship, :sponsor, :login)
    assert_equal "public", v3.dig(:sponsorship, :privacy_level)
    assert_equal tier.global_relay_id, v3.dig(:sponsorship, :tier, :node_id)
    assert_equal tier.monthly_price_in_cents, v3.dig(:sponsorship, :tier, :monthly_price_in_cents)
    assert v3.dig(:sponsorship, :tier, :is_custom_amount)
    refute v3.dig(:sponsorship, :tier, :is_one_time)
    refute_includes v3.keys, :changes
    refute_includes v3.keys, :effective_date
  end

  test "public sponsorship of an org" do
    sponsorship = create(:sponsorship, sponsorable: @sponsored_org)
    sponsor = sponsorship.sponsor
    tier = sponsorship.subscription_item.subscribable
    event = Hook::Event::SponsorshipEvent.new(
      action: @action,
      sponsorship_id: sponsorship.id,
      actor_id: sponsor.id,
      current_tier_id: tier.id,
    )

    payload = Hook::Payload::SponsorshipPayload.new(event)
    v3 = payload.to_hash

    assert_equal @action, v3[:action]
    assert_equal sponsor.login, v3.dig(:sender, :login)
    assert_equal sponsorship.global_relay_id, v3.dig(:sponsorship, :node_id)
    assert_equal @sponsored_org.login, v3.dig(:sponsorship, :sponsorable, :login)
    assert_equal @sponsored_org.login, v3.dig(:sponsorship, :maintainer, :login)
    assert_equal sponsorship.sponsor.login, v3.dig(:sponsorship, :sponsor, :login)
    assert_equal "public", v3.dig(:sponsorship, :privacy_level)
    assert_equal tier.global_relay_id, v3.dig(:sponsorship, :tier, :node_id)
    assert_equal tier.monthly_price_in_cents, v3.dig(:sponsorship, :tier, :monthly_price_in_cents)
    refute_includes v3.keys, :changes
    refute_includes v3.keys, :effective_date
  end

  test "private sponsorship of a user" do
    sponsorship = create(:sponsorship, :private, sponsorable: @sponsored_user)
    sponsor = sponsorship.sponsor
    tier = sponsorship.subscription_item.subscribable
    event = Hook::Event::SponsorshipEvent.new(
      action: @action,
      sponsorship_id: sponsorship.id,
      actor_id: sponsor.id,
      current_tier_id: tier.id,
    )

    payload = Hook::Payload::SponsorshipPayload.new(event)
    v3 = payload.to_hash

    assert_equal @action, v3[:action]
    assert_equal sponsor.login, v3.dig(:sender, :login)
    assert_equal sponsorship.global_relay_id, v3.dig(:sponsorship, :node_id)
    assert_equal @sponsored_user.login, v3.dig(:sponsorship, :sponsorable, :login)
    assert_equal @sponsored_user.login, v3.dig(:sponsorship, :maintainer, :login)
    assert_equal sponsor.login, v3.dig(:sponsorship, :sponsor, :login)
    assert_equal "private", v3.dig(:sponsorship, :privacy_level)
    assert_equal tier.global_relay_id, v3.dig(:sponsorship, :tier, :node_id)
    assert_equal tier.monthly_price_in_cents, v3.dig(:sponsorship, :tier, :monthly_price_in_cents)
    refute_includes v3.keys, :changes
    refute_includes v3.keys, :effective_date
  end

  test "includes changes when present" do
    sponsorship = create(:sponsorship, sponsorable: @sponsored_user)
    sponsor = sponsorship.sponsor
    tier = sponsorship.subscription_item.subscribable
    previous_tier = create(:sponsors_tier)
    event = Hook::Event::SponsorshipEvent.new(
      action: :edited,
      sponsorship_id: sponsorship.id,
      actor_id: sponsor.id,
      changes: { privacy_level: { from: "private" } },
      current_tier_id: tier.id,
      previous_tier_id: previous_tier.id,
    )

    payload = Hook::Payload::SponsorshipPayload.new(event)
    v3 = payload.to_hash

    assert_equal :edited, v3[:action]
    assert_equal sponsor.login, v3.dig(:sender, :login)
    assert_equal sponsorship.global_relay_id, v3.dig(:sponsorship, :node_id)
    assert_equal @sponsored_user.login, v3.dig(:sponsorship, :sponsorable, :login)
    assert_equal @sponsored_user.login, v3.dig(:sponsorship, :maintainer, :login)
    assert_equal sponsor.login, v3.dig(:sponsorship, :sponsor, :login)
    assert_equal "public", v3.dig(:sponsorship, :privacy_level)
    assert_equal tier.global_relay_id, v3.dig(:sponsorship, :tier, :node_id)
    assert_equal tier.monthly_price_in_cents, v3.dig(:sponsorship, :tier, :monthly_price_in_cents)
    assert_equal "private", v3.dig(:changes, :privacy_level, :from)
    assert_equal previous_tier.global_relay_id, v3.dig(:changes, :tier, :from, :node_id)
    assert_equal previous_tier.monthly_price_in_cents, v3.dig(:changes, :tier, :from, :monthly_price_in_cents)
    refute_includes v3.keys, :effective_date
  end

  test "pending tier change" do
    sponsorship = create(:sponsorship, sponsorable: @sponsored_user)
    sponsor = sponsorship.sponsor
    current_tier = sponsorship.subscription_item.subscribable
    pending_change_tier = create(:sponsors_tier)
    pending_change_on = Date.new(2020, 1, 10)
    event = Hook::Event::SponsorshipEvent.new(
      action: :pending_tier_change,
      sponsorship_id: sponsorship.id,
      actor_id: sponsor.id,
      current_tier_id: current_tier.id,
      pending_change_tier_id: pending_change_tier.id,
      pending_change_on: pending_change_on,
    )

    payload = Hook::Payload::SponsorshipPayload.new(event)
    v3 = payload.to_hash

    assert_equal :pending_tier_change, v3[:action]
    assert_equal sponsor.login, v3.dig(:sender, :login)
    assert_equal sponsorship.global_relay_id, v3.dig(:sponsorship, :node_id)
    assert_equal @sponsored_user.login, v3.dig(:sponsorship, :sponsorable, :login)
    assert_equal @sponsored_user.login, v3.dig(:sponsorship, :maintainer, :login)
    assert_equal sponsor.login, v3.dig(:sponsorship, :sponsor, :login)
    assert_equal "public", v3.dig(:sponsorship, :privacy_level)
    assert_equal pending_change_tier.global_relay_id, v3.dig(:sponsorship, :tier, :node_id)
    assert_equal pending_change_tier.monthly_price_in_cents, v3.dig(:sponsorship, :tier, :monthly_price_in_cents)
    assert_equal current_tier.global_relay_id, v3.dig(:changes, :tier, :from, :node_id)
    assert_equal current_tier.monthly_price_in_cents, v3.dig(:changes, :tier, :from, :monthly_price_in_cents)
    assert_equal pending_change_on.to_datetime.iso8601, v3[:effective_date]
  end

  test "pending cancellation" do
    sponsorship = create(:sponsorship, sponsorable: @sponsored_user)
    sponsor = sponsorship.sponsor
    sponsors_tier = sponsorship.subscription_item.subscribable
    pending_change_on = Date.new(2020, 1, 10)
    event = Hook::Event::SponsorshipEvent.new(
      action: :pending_cancellation,
      sponsorship_id: sponsorship.id,
      actor_id: sponsor.id,
      current_tier_id: sponsors_tier.id,
      pending_change_on: pending_change_on,
    )

    payload = Hook::Payload::SponsorshipPayload.new(event)
    v3 = payload.to_hash

    assert_equal :pending_cancellation, v3[:action]
    assert_equal sponsor.login, v3.dig(:sender, :login)
    assert_equal sponsorship.global_relay_id, v3.dig(:sponsorship, :node_id)
    assert_equal @sponsored_user.login, v3.dig(:sponsorship, :sponsorable, :login)
    assert_equal @sponsored_user.login, v3.dig(:sponsorship, :maintainer, :login)
    assert_equal sponsor.login, v3.dig(:sponsorship, :sponsor, :login)
    assert_equal "public", v3.dig(:sponsorship, :privacy_level)
    assert_equal sponsors_tier.global_relay_id, v3.dig(:sponsorship, :tier, :node_id)
    assert_equal sponsors_tier.monthly_price_in_cents, v3.dig(:sponsorship, :tier, :monthly_price_in_cents)
    refute_includes v3.keys, :changes
    assert_equal pending_change_on.to_datetime.iso8601, v3[:effective_date]
  end
end
