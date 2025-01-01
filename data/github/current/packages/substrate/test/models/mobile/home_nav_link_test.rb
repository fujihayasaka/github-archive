# typed: true
# frozen_string_literal: true

require "test_helper"

class MobileHomeNavLinkTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  NavLink = ::Mobile::HomeNavLink

  fixtures do
    @user = create(:user)
  end

  setup do
    @test_key = "#{NavLink::STORE_KEY_PREFIX}:#{NavLink::STORE_KEY_VERSION}:#{@user.id}"

    # Setup is links reversed and all hidden

    @test_links = NavLink.links_map.map do |identifier, enum_value|
      NavLink.new(identifier: identifier, enum_value: enum_value, hidden: true)
    end.reverse

    @test_value = @test_links.map(&:to_kv_value).join(",")

    GitHub.kv.set(@test_key, @test_value) # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  test "has the correct data configuration" do
    assert_equal %w(
      issues
      pull_requests
      discussions
      projects
      repositories
      organizations
      starred
    ), NavLink::ALL_LINKS.keys

    assert_equal %w(projects), NavLink::ENTERPRISE_EXCLUSIONS

    assert_equal %w(
      issues
      pull_requests
      discussions
      repositories
      organizations
      starred
    ), NavLink::ENTERPRISE_LINKS.keys
  end

  test "links_map has unique values" do
    assert_equal(
      NavLink.links_map.values.uniq,
      NavLink.links_map.values,
      "All link identifier values must be unique"
    )
  end

  test "generates a GitHub::KV key for a user" do
    assert_equal(@test_key, NavLink.store_key_for_user(@user))
  end

  context "async retrieving all links for a user" do
    test "returns a Promise of nav links" do
      promise = NavLink.async_all_for_user(@user)
      assert_equal @test_links, promise.sync
    end
  end

  context "retrieving all links for a user" do
    test "fetches successfully from GitHub::KV" do
      assert_equal @test_links, NavLink.all_for_user(@user)
    end

    test "returns default links when GitHub::KV is unavailable" do
      GitHub.kv.stubs(:get).with(@test_key).raises(GitHub::KV::UnavailableError) # rubocop:todo GitHub/DoNotUseGlobalKv
      assert_equal NavLink.default_links, NavLink.all_for_user(@user)
    end
  end

  context "building links from a raw string of nav link data" do
    test "returns correct link objects" do
      assert_equal @test_links, NavLink.links_from_raw_value(@test_value)
    end

    test "returns default links when the value is blank" do
      assert_equal(
        NavLink.default_links,
        NavLink.links_from_raw_value("")
      )
    end

    test "skips unknown links identifiers and deduplicates" do
      malformed_value = "88888:0,#{@test_value},99999:0,#{@test_value}"

      assert_equal(
        @test_links,
        NavLink.links_from_raw_value(malformed_value)
      )
    end

    test "appends missing links to the end of the links retrieved" do
      # Simulating that storage has some data that is valid, but incomplete.
      # The expectation is that missing links will be automatically added to the returned links.
      *other_links, the_one_link = NavLink.default_links

      expected_links = [the_one_link, *other_links]

      actual_links = NavLink.links_from_raw_value(the_one_link.to_kv_value)

      assert_equal expected_links, actual_links
    end
  end

  context "updating stored links for a user" do
    test "stores data in the expected format in GitHub::KV" do
      GitHub.kv.del(@test_key) # rubocop:todo GitHub/DoNotUseGlobalKv

      assert_equal NavLink.default_links, NavLink.all_for_user(@user)

      sorted_links = @test_links.map(&:identifier)
      hidden_links = @test_links.select(&:hidden?).map(&:identifier)

      NavLink.update_for_user!(@user, sorted_links: sorted_links, hidden_links: hidden_links)

      assert_equal @test_value, GitHub.kv.get(@test_key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
      assert_equal @test_links, NavLink.all_for_user(@user)
    end

    test "does not store invalid nav links" do
      NavLink.update_for_user!(@user, sorted_links: ["woahwoahwoah"])
      assert_predicate GitHub.kv.get(@test_key).value!, :blank? # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    test "instruments an audit event" do
      sorted_links = @test_links.map(&:identifier)
      hidden_links = @test_links.filter_map { |link| link.identifier if link.hidden? }

      audit_event = assert_performed_audit_entries(count: 1, only: "user_dashboard.nav_links_update") do
        NavLink.update_for_user!(@user, sorted_links: sorted_links, hidden_links: hidden_links)
      end.first

      assert_subset_hash({
        action: "user_dashboard.nav_links_update",
        user: @user.login,
        user_id: @user.id,
        user_dashboard_links: @test_value
      }, audit_event)
    end
  end

  if GitHub.enterprise?
    test "does not include dotcom-only links" do
      assert_equal NavLink.default_links.map(&:identifier), NavLink::ENTERPRISE_LINKS.keys
    end

    test "does not store dotcom-only links" do
      NavLink.update_for_user!(@user, sorted_links: NavLink::ALL_LINKS.keys)
      assert_equal NavLink.all_for_user(@user).map(&:identifier), NavLink::ENTERPRISE_LINKS.keys
    end
  end
end
