# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadPingPayloadTest < GitHub::TestCase
  fixtures do
    @integration = create :integration, :with_active_hook, default_events: %w(pull_request membership),
      default_permissions: { "pull_requests" => :read, "members" => :read }
    org = create(:organization)

    @repo_hook = create :hook, :web, events: %w(pull_request issues)
    @integration_hook = @integration.hook
    @org_hook = create :hook, :org, installation_target: org, events: %w(pull_request issues)
    @business = create :business
    @business_hook = create :hook, installation_target: @business
  end

  test "v3 with a hook installed for a Repository" do
    event = Hook::Event::PingEvent.new hook_id: @repo_hook.id
    payload = Hook::Payload::PingPayload.new event

    v3 = payload.to_hash

    assert_includes GitHub::Config::Octocat::ZEN_PHRASES, v3[:zen]
    assert_equal @repo_hook.id, v3[:hook_id]
    assert_equal "web", v3[:hook][:name]
    assert_same_elements %w(pull_request issues), v3[:hook][:events]
    assert_equal "Repository", v3[:hook][:type]
  end

  test "v3 with a hook installed for an Organization" do
    event = Hook::Event::PingEvent.new hook_id: @org_hook.id
    payload = Hook::Payload::PingPayload.new event

    v3 = payload.to_hash

    assert_includes GitHub::Config::Octocat::ZEN_PHRASES, v3[:zen]
    assert_equal @org_hook.id, v3[:hook_id]
    assert_equal "web", v3[:hook][:name]
    assert_same_elements %w(pull_request issues), v3[:hook][:events]
    assert_equal "Organization", v3[:hook][:type]
  end

  test "v3 with a hook installed for a Business" do
    event = Hook::Event::PingEvent.new hook_id: @business_hook.id
    payload = Hook::Payload::PingPayload.new event

    v3 = payload.to_hash

    assert_includes GitHub::Config::Octocat::ZEN_PHRASES, v3[:zen]
    assert_equal @business_hook.id, v3[:hook_id]
    assert_equal "web", v3[:hook][:name]
    assert_equal "Enterprise", v3[:hook][:type]
    assert_equal @business.id, v3[:hook][:enterprise_id]
  end

  test "v3 with a hook installed for a GitHub App" do
    event = Hook::Event::PingEvent.new hook_id: @integration_hook.id
    payload = Hook::Payload::PingPayload.new event

    v3 = payload.to_hash

    assert_includes GitHub::Config::Octocat::ZEN_PHRASES, v3[:zen]
    assert_equal @integration_hook.id, v3[:hook_id]
    assert_equal "web", v3[:hook][:name]
    assert_same_elements %w(pull_request membership), v3[:hook][:events]
    assert_equal "App", v3[:hook][:type]
    assert_equal @integration.id, v3[:hook][:app_id]
    assert_match /app\/hook\/deliveries/, v3[:hook][:deliveries_url]
  end

  test "v3 with a hook installed for a Marketplace Listing" do
    listing = create(:marketplace_listing)
    listing_hook = create :hook, :web, events: %w(marketplace_purchase),
      installation_target: listing
    event = Hook::Event::PingEvent.new hook_id: listing_hook.id
    payload = Hook::Payload::PingPayload.new event

    v3 = payload.to_hash

    assert_includes GitHub::Config::Octocat::ZEN_PHRASES, v3[:zen]
    assert_equal listing_hook.id, v3[:hook_id]
    assert_equal "web", v3[:hook][:name]
    assert_same_elements %w(marketplace_purchase), v3[:hook][:events]
    assert_equal "Marketplace::Listing", v3[:hook][:type]
    assert_equal listing.id, v3[:hook][:marketplace_listing_id]
  end
end
