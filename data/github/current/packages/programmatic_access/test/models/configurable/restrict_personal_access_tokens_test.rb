# typed: true
# frozen_string_literal: true

require "test_helper"

class RestrictPersonalAccessTokensTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create :business_plus_org, admin: @user

    @business = create :business, owners: [@user]
    @business_owned_org = create :business_plus_org, admin: @user
    @business.add_organization(@business_owned_org)
  end

  context "#permit_personal_access_tokens" do
    test "enables an organization" do
      @org.permit_personal_access_tokens(actor: @user)

      assert_predicate @org, :personal_access_tokens_allowed?
      assert_predicate @org, :personal_access_tokens_delegated_policy?
      refute_predicate @org, :personal_access_tokens_restricted_policy?
    end

    test "enables an org owned by a business" do
      @business_owned_org.permit_personal_access_tokens(actor: @user)

      assert_predicate @business_owned_org, :personal_access_tokens_allowed?
      assert_predicate @business_owned_org, :personal_access_tokens_delegated_policy?
    end

    test "enables a business and the organizations that belong to it" do
      @business.permit_personal_access_tokens(actor: @user)

      assert_predicate @business, :personal_access_tokens_allowed?
      assert_predicate @business_owned_org, :personal_access_tokens_allowed?

      refute_predicate @business, :personal_access_tokens_restricted?
      refute_predicate @business_owned_org, :personal_access_tokens_restricted?

      refute_predicate @business, :personal_access_tokens_restricted_policy?
      refute_predicate @business_owned_org, :personal_access_tokens_restricted_policy?
    end

    test "cannot enable an org that belongs to a business if the business does not allow it" do
      @business.restrict_personal_access_tokens(actor: @user)

      assert_raises(Configurable::RestrictPersonalAccessTokens::ConfigurationError) do
        @business_owned_org.permit_personal_access_tokens(actor: @user)
      end

      refute_predicate @business_owned_org, :personal_access_tokens_allowed?
      assert_predicate @business_owned_org, :personal_access_tokens_restricted?
      assert_predicate @business_owned_org, :personal_access_tokens_restricted_policy?
    end
  end

  context "#restrict_personal_access_tokens" do
    test "disables access for an org" do
      @org.permit_personal_access_tokens(actor: @user)

      assert_predicate @org, :personal_access_tokens_delegated_policy?
      refute_predicate @org, :personal_access_tokens_restricted?
      assert_predicate @org, :personal_access_tokens_allowed?

      @org.restrict_personal_access_tokens(actor: @user)

      assert_predicate @org, :personal_access_tokens_delegated_policy?
      assert_predicate @org, :personal_access_tokens_restricted?
      refute_predicate @org, :personal_access_tokens_allowed?
    end

    test "disables an org owned by a business" do
      @business_owned_org.restrict_personal_access_tokens(actor: @user)

      refute_predicate @business_owned_org, :personal_access_tokens_allowed?
      assert_predicate @business_owned_org, :personal_access_tokens_delegated_policy?
    end


    test "disables access for a business and for its organizations" do
      @business.permit_personal_access_tokens(actor: @user)
      @business_owned_org.permit_personal_access_tokens(actor: @user)

      refute_predicate @business, :personal_access_tokens_restricted?
      refute_predicate @business_owned_org, :personal_access_tokens_restricted?

      @business.restrict_personal_access_tokens(actor: @user)
      @business_owned_org.reload

      assert_predicate @business, :personal_access_tokens_restricted?
      assert_predicate @business_owned_org, :personal_access_tokens_restricted?

      refute_predicate @business, :personal_access_tokens_allowed?
      refute_predicate @business_owned_org, :personal_access_tokens_allowed?
    end

    test "does not allow a business owned org to disable access if the business has enforced it" do
      @business.permit_personal_access_tokens(actor: @user)

      assert_raises(Configurable::RestrictPersonalAccessTokens::ConfigurationError) do
        @business_owned_org.restrict_personal_access_tokens(actor: @user)
      end

      assert_predicate @business_owned_org, :personal_access_tokens_allowed?
    end
  end

  context "#reset_personal_access_tokens_restriction" do
    test "reset restriction for an org" do
      @org.restrict_personal_access_tokens(actor: @user)
      assert_predicate @org, :personal_access_tokens_restricted?
      assert_predicate @org, :personal_access_tokens_delegated_policy?

      @org.reset_personal_access_tokens_restriction(actor: @user)
      refute_predicate @org, :personal_access_tokens_restricted?
      assert_predicate @org, :personal_access_tokens_delegated_policy?
    end

    test "reset restriction for a business and its organizations" do
      @business.restrict_personal_access_tokens(actor: @user)

      refute_predicate @business, :personal_access_tokens_delegated_policy?

      assert_predicate @business, :personal_access_tokens_restricted?
      assert_predicate @business_owned_org, :personal_access_tokens_restricted?

      @business.reset_personal_access_tokens_restriction(actor: @user)
      @business_owned_org.reload

      assert_predicate @business, :personal_access_tokens_delegated_policy?

      refute_predicate @business, :personal_access_tokens_restricted?
      refute_predicate @business_owned_org, :personal_access_tokens_restricted?
    end

    test "reset restriction for a business owned org when policy bound has no effect" do
      @business.restrict_personal_access_tokens(actor: @user)
      assert_predicate @business_owned_org, :personal_access_tokens_restricted?

      @business_owned_org.reset_personal_access_tokens_restriction(actor: @user)
      assert_predicate @business_owned_org, :personal_access_tokens_restricted?
    end
  end

  context "#personal_access_tokens_allowed?" do
    test "is true by default for a stand alone organization" do
      assert_predicate @org, :personal_access_tokens_allowed?
    end

    test "is true by default for a business" do
      assert_predicate @business, :personal_access_tokens_allowed?
    end

    test "is true by default for business owned organizations" do
      assert_predicate @business_owned_org, :personal_access_tokens_allowed?
    end
  end

  context "#personal_access_tokens_restricted?" do
    test "is false by default for stand along organizations" do
      refute_predicate @org, :personal_access_tokens_restricted?
    end

    test "is false by default for business owned organizations" do
      refute_predicate @business_owned_org, :personal_access_tokens_restricted?
    end

    test "is false by default for businesses" do
      refute_predicate @business, :personal_access_tokens_restricted?
    end
  end

  context "instrumentation" do
    context "allow" do
      test "on an org" do
        events = subscribe("personal_access_token.access_restriction_disabled")
        @org.permit_personal_access_tokens(actor: @user)

        expected_payload = {
          programmatic_access_type: "fine-grained personal access tokens",
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
        events = subscribe("personal_access_token.access_restriction_disabled")
        @business.permit_personal_access_tokens(actor: @user)

        expected_payload = {
          programmatic_access_type: "fine-grained personal access tokens",
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
        events = subscribe("personal_access_token.access_restriction_disabled")
        @business_owned_org.permit_personal_access_tokens(actor: @user)

        expected_payload = {
          programmatic_access_type: "fine-grained personal access tokens",
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

    context "deny" do
      test "on an org" do
        @org.permit_personal_access_tokens(actor: @user)

        events = subscribe("personal_access_token.access_restriction_enabled")
        @org.restrict_personal_access_tokens(actor: @user)

        expected_payload = {
          programmatic_access_type: "fine-grained personal access tokens",
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
        @business.permit_personal_access_tokens(actor: @user)

        events = subscribe("personal_access_token.access_restriction_enabled")
        @business.restrict_personal_access_tokens(actor: @user)

        expected_payload = {
          programmatic_access_type: "fine-grained personal access tokens",
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
        @business_owned_org.permit_personal_access_tokens(actor: @user)

        events = subscribe("personal_access_token.access_restriction_enabled")
        @business_owned_org.restrict_personal_access_tokens(actor: @user)

        expected_payload = {
          programmatic_access_type: "fine-grained personal access tokens",
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

    context "reset" do
      test "on an org" do
        @org.permit_personal_access_tokens(actor: @user)

        events = subscribe("personal_access_token.access_restriction_reset")
        @org.reset_personal_access_tokens_restriction(actor: @user)

        expected_payload = {
          programmatic_access_type: "fine-grained personal access tokens",
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
        @business.permit_personal_access_tokens(actor: @user)

        events = subscribe("personal_access_token.access_restriction_reset")
        @business.reset_personal_access_tokens_restriction(actor: @user)

        expected_payload = {
          programmatic_access_type: "fine-grained personal access tokens",
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
        @business_owned_org.permit_personal_access_tokens(actor: @user)

        events = subscribe("personal_access_token.access_restriction_reset")
        @business_owned_org.reset_personal_access_tokens_restriction(actor: @user)

        expected_payload = {
          programmatic_access_type: "fine-grained personal access tokens",
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
