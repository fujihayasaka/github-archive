# typed: true
# frozen_string_literal: true

require "test_helper"

class RestrictLegacyPersonalAccessTokensTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create :business_plus_org, admin: @user

    @business = create :business, owners: [@user]
    @business_owned_org = create :business_plus_org, admin: @user
    @business.add_organization(@business_owned_org)
  end

  # Make sure configuration entries are not memoized
  def reload_configs
    [
      @org, @business, @business_owned_org
    ].map(&:config).each(&:reset)
  end

  context "#restrict_legacy_personal_access_tokens" do
    test "restricts an org" do
      @org.restrict_legacy_personal_access_tokens(actor: @user)

      assert_predicate @org, :legacy_personal_access_tokens_restricted?
      assert_predicate @org, :legacy_personal_access_tokens_delegated_policy?
      refute_predicate @org, :legacy_personal_access_tokens_restricted_policy?
    end

    test "restricts a business and orgs that belong to it" do
      @business.restrict_legacy_personal_access_tokens(actor: @user)

      assert_predicate @business, :legacy_personal_access_tokens_restricted?
      assert_predicate @business_owned_org, :legacy_personal_access_tokens_restricted?

      refute_predicate @business, :legacy_personal_access_tokens_restricted_policy?
      assert_predicate @business_owned_org, :legacy_personal_access_tokens_restricted_policy?
    end

    test "restricts an org that belongs to a business, but not the parent business" do
      @business_owned_org.restrict_legacy_personal_access_tokens(actor: @user)

      refute_predicate @business, :legacy_personal_access_tokens_restricted?
      assert_predicate @business_owned_org, :legacy_personal_access_tokens_restricted?

      refute_predicate @business, :legacy_personal_access_tokens_restricted_policy?
      refute_predicate @business_owned_org, :legacy_personal_access_tokens_restricted_policy?
    end

    test "raises an error if the business is permitting pats" do
      @business.permit_legacy_personal_access_tokens(actor: @user)
      @business_owned_org.reload

      assert_predicate @business_owned_org, :legacy_personal_access_tokens_permitted_policy?

      assert_raises(Configurable::RestrictLegacyPersonalAccessTokens::ConfigurationError) do
        @business_owned_org.restrict_legacy_personal_access_tokens(actor: @user)
      end

      refute_predicate @business, :legacy_personal_access_tokens_restricted?
      refute_predicate @business_owned_org, :legacy_personal_access_tokens_restricted?
    end
  end

  context "#permit_legacy_personal_access_tokens" do
    test "an org" do
      @org.restrict_legacy_personal_access_tokens(actor: @user)
      assert_predicate @org, :legacy_personal_access_tokens_restricted?
      assert_predicate @org, :legacy_personal_access_tokens_delegated_policy?

      @org.permit_legacy_personal_access_tokens(actor: @user)
      reload_configs

      refute_predicate @org, :legacy_personal_access_tokens_restricted?
      assert_predicate @org, :legacy_personal_access_tokens_delegated_policy?
    end

    test "an org that belongs to a business" do
      @business_owned_org.restrict_legacy_personal_access_tokens(actor: @user)
      assert_predicate @business_owned_org, :legacy_personal_access_tokens_restricted?
      assert_predicate @business_owned_org, :legacy_personal_access_tokens_delegated_policy?

      @business_owned_org.permit_legacy_personal_access_tokens(actor: @user)
      reload_configs

      refute_predicate @business_owned_org, :legacy_personal_access_tokens_restricted?
      assert_predicate @business_owned_org, :legacy_personal_access_tokens_delegated_policy?
    end

    test "a business and the orgs that belong to it" do
      @business.restrict_legacy_personal_access_tokens(actor: @user)
      assert_predicate @business, :legacy_personal_access_tokens_restricted?
      assert_predicate @business_owned_org, :legacy_personal_access_tokens_restricted?

      @business.permit_legacy_personal_access_tokens(actor: @user)
      reload_configs

      refute_predicate @business, :legacy_personal_access_tokens_restricted?
      refute_predicate @business_owned_org, :legacy_personal_access_tokens_restricted?
    end

    test "raises an error if an business owned org tries to override the policy" do
      @business.restrict_legacy_personal_access_tokens(actor: @user)
      assert_predicate @business, :legacy_personal_access_tokens_restricted?
      assert_predicate @business_owned_org, :legacy_personal_access_tokens_restricted?

      assert_raises(Configurable::RestrictLegacyPersonalAccessTokens::ConfigurationError) do
        @business_owned_org.permit_legacy_personal_access_tokens(actor: @user)
      end

      assert_predicate @business, :legacy_personal_access_tokens_restricted?
      assert_predicate @business_owned_org, :legacy_personal_access_tokens_restricted?
    end
  end

  context "#reset_legacy_personal_access_tokens" do
    test "reset restriction for an org" do
      @org.restrict_legacy_personal_access_tokens(actor: @user)
      assert_predicate @org, :legacy_personal_access_tokens_restricted?
      assert_predicate @org, :legacy_personal_access_tokens_delegated_policy?

      @org.reset_legacy_personal_access_tokens_restriction(actor: @user)
      refute_predicate @org, :legacy_personal_access_tokens_restricted?
      assert_predicate @org, :legacy_personal_access_tokens_delegated_policy?
    end

    test "reset restriction for a business and its organizations" do
      @business.restrict_legacy_personal_access_tokens(actor: @user)

      refute_predicate @business, :legacy_personal_access_tokens_delegated_policy?

      assert_predicate @business, :legacy_personal_access_tokens_restricted?
      assert_predicate @business_owned_org, :legacy_personal_access_tokens_restricted?

      @business.reset_legacy_personal_access_tokens_restriction(actor: @user)
      @business_owned_org.reload

      assert_predicate @business, :legacy_personal_access_tokens_delegated_policy?

      refute_predicate @business, :legacy_personal_access_tokens_restricted?
      refute_predicate @business_owned_org, :legacy_personal_access_tokens_restricted?
    end

    test "reset restriction for a business owned org when policy bound has no effect" do
      @business.restrict_legacy_personal_access_tokens(actor: @user)
      assert_predicate @business_owned_org, :legacy_personal_access_tokens_restricted?

      @business_owned_org.reset_legacy_personal_access_tokens_restriction(actor: @user)
      assert_predicate @business_owned_org, :legacy_personal_access_tokens_restricted?
    end
  end

  context "instrumentation" do
    context "restrict" do
      test "on an org" do
        events = subscribe("personal_access_token.access_restriction_enabled")
        @org.restrict_legacy_personal_access_tokens(actor: @user)

        expected_payload = {
          programmatic_access_type: "personal access tokens (classic)",
          user: @user.login,
          user_id: @user.id,
          org: @org.login,
          org_id: @org.id,
        }

        assert event = events.pop, "An event was expected"
        assert_equal "personal_access_token.access_restriction_enabled", event.name

        assert_same_hash expected_payload, event.payload
      end

      test "on a business" do
        events = subscribe("personal_access_token.access_restriction_enabled")
        @business.restrict_legacy_personal_access_tokens(actor: @user)

        expected_payload = {
          programmatic_access_type: "personal access tokens (classic)",
          user: @user.login,
          user_id: @user.id,
          business: @business.slug,
          business_id: @business.id,
        }

        assert event = events.pop, "An event was expected"
        assert_equal "personal_access_token.access_restriction_enabled", event.name

        assert_same_hash expected_payload, event.payload
      end

      test "on an org owned by a business" do
        events = subscribe("personal_access_token.access_restriction_enabled")
        @business_owned_org.restrict_legacy_personal_access_tokens(actor: @user)

        expected_payload = {
          programmatic_access_type: "personal access tokens (classic)",
          user: @user.login,
          user_id: @user.id,
          org: @business_owned_org.login,
          org_id: @business_owned_org.id,
          business: @business.slug,
          business_id: @business.id,
        }

        assert event = events.pop, "An event was expected"
        assert_equal "personal_access_token.access_restriction_enabled", event.name

        assert_same_hash expected_payload, event.payload
      end
    end

    context "permit" do
      test "on an org" do
        @org.restrict_legacy_personal_access_tokens(actor: @user)

        events = subscribe("personal_access_token.access_restriction_disabled")
        @org.permit_legacy_personal_access_tokens(actor: @user)

        expected_payload = {
          programmatic_access_type: "personal access tokens (classic)",
          user: @user.login,
          user_id: @user.id,
          org: @org.login,
          org_id: @org.id,
        }

        assert event = events.pop, "An event was expected"
        assert_equal "personal_access_token.access_restriction_disabled", event.name

        assert_same_hash expected_payload, event.payload
      end

      test "on a business" do
        @business.restrict_legacy_personal_access_tokens(actor: @user)

        events = subscribe("personal_access_token.access_restriction_disabled")
        @business.permit_legacy_personal_access_tokens(actor: @user)

        expected_payload = {
          programmatic_access_type: "personal access tokens (classic)",
          user: @user.login,
          user_id: @user.id,
          business: @business.slug,
          business_id: @business.id,
        }

        assert event = events.pop, "An event was expected"
        assert_equal "personal_access_token.access_restriction_disabled", event.name

        assert_same_hash expected_payload, event.payload
      end

      test "on an org owned by a business" do
        @business_owned_org.restrict_legacy_personal_access_tokens(actor: @user)

        events = subscribe("personal_access_token.access_restriction_disabled")
        @business_owned_org.permit_legacy_personal_access_tokens(actor: @user)

        expected_payload = {
          programmatic_access_type: "personal access tokens (classic)",
          user: @user.login,
          user_id: @user.id,
          org: @business_owned_org.login,
          org_id: @business_owned_org.id,
          business: @business.slug,
          business_id: @business.id,
        }

        assert event = events.pop, "An event was expected"
        assert_equal "personal_access_token.access_restriction_disabled", event.name

        assert_same_hash expected_payload, event.payload
      end
    end

    context "reset" do
      test "on an org" do
        @org.restrict_legacy_personal_access_tokens(actor: @user)

        events = subscribe("personal_access_token.access_restriction_reset")
        @org.reset_legacy_personal_access_tokens_restriction(actor: @user)

        expected_payload = {
          programmatic_access_type: "personal access tokens (classic)",
          user: @user.login,
          user_id: @user.id,
          org: @org.login,
          org_id: @org.id,
        }

        assert event = events.pop, "An event was expected"
        assert_equal "personal_access_token.access_restriction_reset", event.name

        assert_same_hash expected_payload, event.payload
      end

      test "on a business" do
        @business.restrict_legacy_personal_access_tokens(actor: @user)

        events = subscribe("personal_access_token.access_restriction_reset")
        @business.reset_legacy_personal_access_tokens_restriction(actor: @user)

        expected_payload = {
          programmatic_access_type: "personal access tokens (classic)",
          user: @user.login,
          user_id: @user.id,
          business: @business.slug,
          business_id: @business.id,
        }

        assert event = events.pop, "An event was expected"
        assert_equal "personal_access_token.access_restriction_reset", event.name

        assert_same_hash expected_payload, event.payload
      end

      test "on an org owned by a business" do
        @business_owned_org.restrict_legacy_personal_access_tokens(actor: @user)

        events = subscribe("personal_access_token.access_restriction_reset")
        @business_owned_org.reset_legacy_personal_access_tokens_restriction(actor: @user)

        expected_payload = {
          programmatic_access_type: "personal access tokens (classic)",
          user: @user.login,
          user_id: @user.id,
          org: @business_owned_org.login,
          org_id: @business_owned_org.id,
          business: @business.slug,
          business_id: @business.id,
        }

        assert event = events.pop, "An event was expected"
        assert_equal "personal_access_token.access_restriction_reset", event.name

        assert_same_hash expected_payload, event.payload
      end
    end
  end
end
