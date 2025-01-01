# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationInvitationRateLimitPolicyTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @org = create(:organization)
  end

  def limit_for(org)
    OrganizationInvitation::RateLimitPolicy.new(org)
  end

  context "untrusted" do
    test "a new organization is untrusted" do
      new_org = create :free_org
      limit   = limit_for(new_org)

      refute_predicate limit, :trusted?
      assert_equal :untrusted, limit.classification
    end
  end

  context "trusted" do
    test "an older organization is trusted" do
      trusted = 1.day + OrganizationInvitation::RateLimitPolicy::TRUSTED_AGE_REQUIREMENT
      old_org = create :free_org, created_at: trusted.ago
      limit   = limit_for(old_org)

      assert_predicate limit, :trusted?
      assert_equal :trusted, limit.classification
    end
  end

  context "paying" do
    test "an organization on a paid plan is trusted, paying" do
      paid_org = create(:organization)
      limit   = limit_for(paid_org)

      assert_predicate paid_org.plan, :paid?

      assert_predicate limit, :trusted?
      assert_equal :paying, limit.classification
    end
  end

  context "custom" do
    test "an organization with a custom rate limit" do
      limit = limit_for(@org)

      GitHub.kv.set(limit.custom_limit_key, 50_000_000.to_s) # rubocop:todo GitHub/DoNotUseGlobalKv

      assert_predicate limit, :custom?
      assert_equal :custom, limit.classification

      assert_equal 50_000_000, limit.limit
    end

    test "loads the custom limit" do
      limit = limit_for(@org)

      GitHub.kv.set(limit.custom_limit_key, 50_000_000.to_s) # rubocop:todo GitHub/DoNotUseGlobalKv

      assert_equal 50_000_000, limit.limit
    end

    test "#set_custom_limit returns Hash containing success false when unable to parse limit" do
      limit = limit_for(@org)
      assert_equal({ success: false }, limit.set_custom_limit("not a number"))

      refute_predicate limit, :custom?
    end

    test "can be set using #set_custom_limit" do
      limit = limit_for(@org)
      assert_equal(
        { success: true, expires_at: nil },
        limit.set_custom_limit(50_000_000)
      )

      assert_predicate limit, :custom?
      assert_equal :custom, limit.classification

      assert_equal 50_000_000, limit.limit
    end

    test "intruments setting a custom limit" do
      limit = limit_for(@org)

      events = subscribe "org.set_custom_invitation_rate_limit"
      limit.set_custom_limit(50_000_000)

      expected_payload = {
        org: @org.login,
        org_id: @org.id,
        limit: 50_000_000,
      }

      assert event = events.pop, "expected an org.set_custom_invitation_rate_limit event"
      assert_equal expected_payload, event.payload
    end

    test "can be set with an expires_at value using #set_custom_limit" do
      expires_at = Date.parse(3.days.from_now.to_s).to_time
      limit = limit_for(@org)
      assert_equal(
        { success: true, expires_at: expires_at },
        limit.set_custom_limit(50_000_000, expires_at: expires_at)
      )

      assert_predicate limit, :custom?
      assert_equal :custom, limit.classification

      assert_equal 50_000_000, limit.limit
      assert_equal expires_at, limit.custom_limit_expires_at
    end

    test "custom rate limit expires when set with an expires_at value" do
      expires_at = Date.parse(3.days.from_now.to_s).to_time
      limit = limit_for(@org)
      assert_equal(
        { success: true, expires_at: expires_at },
        limit.set_custom_limit(50_000_000, expires_at: expires_at)
      )
      assert_predicate limit, :custom?
      assert_equal 50_000_000, limit.limit
      assert_equal expires_at, limit.custom_limit_expires_at

      Timecop.travel(5.days.from_now) do
        limit = limit_for(@org)
        refute_predicate limit, :custom?
        assert_equal 500, limit.limit
        assert_nil limit.custom_limit_expires_at
      end
    end

    test "can be cleared with clear_custom_limit" do
      limit = limit_for(@org)
      limit.set_custom_limit(50_000_000)

      assert_predicate limit, :custom?
      assert_equal :custom, limit.classification

      assert limit.clear_custom_limit, "should be able to clear custom limit"

      refute_predicate limit, :custom?
      refute_equal :custom, limit.classification

      refute_equal 50_000_000, limit.limit
    end

    test "instruments clearing a custom limit" do
      limit = limit_for(@org)
      limit.set_custom_limit(50_000_000)

      assert_predicate limit, :custom?
      assert_equal :custom, limit.classification

      events = subscribe "org.clear_custom_invitation_rate_limit"
      assert limit.clear_custom_limit, "should be able to clear custom limit"

      expected_payload = {
        org: @org.login,
        org_id: @org.id,
        limit: 500,
      }

      assert event = events.pop, "expected an org.clear_custom_invitation_rate_limit event"
      assert_equal expected_payload, event.payload
    end

    test "record_rate_limited emits dogstats with both action and controller name" do
      limit = limit_for(@org)
      action = "create"
      controller = Orgs::InvitationsController.controller_name
      limit.record_rate_limited("create", controller)
      assert_dogstats_increment(1, "rate_limited", tags: ["action:#{action}", "controller:#{controller}"])
    end
  end
end
