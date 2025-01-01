# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Listings::SecurityAndComplianceTest < GitHub::TestCase
  fixtures do
    enable_feature_flag(:copilot_extendable)
    @listing = create(:marketplace_listing, :verified)
    @draft_listing = create(:marketplace_listing)
    @copilot_listing = create(:marketplace_listing, :copilot, :verified)
  end

  setup do
    @noncompliant_listing = create(:marketplace_listing, :verified)
    @noncompliant_listing.trader_self_certification = nil
    @noncompliant_listing.ai_risk_level = :unspecified
    @noncompliant_listing.third_party_services = nil
    @noncompliant_listing.save(validate: false)
  end

  context "validations" do
    context "dsa validations" do
      test "does not run validations if not saving a change to a dsa attribute" do
        @noncompliant_listing.update(name: "New name")
        assert @noncompliant_listing.valid?
        assert @noncompliant_listing.errors.empty?
      end

      context "when certifying as a trader" do
        test "is valid if there are missing attributes but the listing is still a draft" do
          @draft_listing.update(trader_self_certification: :trader)
          assert @draft_listing.valid?
        end

        test "is invalid if there is no business address" do
          @listing.update(trader_address: nil)
          refute @listing.valid?
          assert_equal "Business address is required", @listing.errors.full_messages.first
        end

        test "is invalid if there is no business id type" do
          @listing.update(trader_id_type: nil)
          refute @listing.valid?
          assert_equal "Business id type is required", @listing.errors.full_messages.first
        end

        test "is invalid if there is no business id" do
          @listing.update(trader_id: nil)
          refute @listing.valid?
          assert_equal "Business id is required", @listing.errors.full_messages.first
        end
      end

      context "when not certifying as a trader" do
        test "is valid" do
          @noncompliant_listing.update(trader_self_certification: :non_trader)
          assert @noncompliant_listing.valid?
        end
      end
    end

    context "ai validations" do
      test "does not run validations if not saving a change to a dsa attribute" do
        @noncompliant_listing.update(name: "New name")
        assert @noncompliant_listing.valid?
        assert @noncompliant_listing.errors.empty?
      end

      test "is valid if all ai attributes are present" do
        assert @listing.is_eu_ai_act_compliant.present?
        assert @listing.ai_risk_level.present?
        assert @listing.llms_in_use.present?
        assert @listing.valid?
      end

      test "is valid if attributes are missing but the listing is still a draft" do
        @draft_listing.update(llms_in_use: nil)
        assert @draft_listing.valid?
      end

      test "is invalid if ai_risk_level is unspecified" do
        @listing.update(ai_risk_level: :unspecified)
        refute @listing.valid?
        assert_equal 'You must specify if your AI system is classified as "high-risk"', @listing.errors.full_messages.first
      end

      test "is invalid if llms_in_use is blank" do
        @listing.update(llms_in_use: nil)
        refute @listing.valid?
        assert_equal "You must list all LLMs that your extension uses", @listing.errors.full_messages.first
      end

      test "is valid if is_eu_ai_act_compliant is false" do
        # This is a "valid" case, but the listing will not be ai compliant
        @listing.update(is_eu_ai_act_compliant: false)
        assert @listing.valid?
      end
    end

    context "security validations" do
      test "does not run validations if not saving a change to a security attribute" do
        @noncompliant_listing.update(name: "New name")
        assert @noncompliant_listing.valid?
        assert @noncompliant_listing.errors.empty?
      end

      test "is valid if all security attributes are present" do
        @listing.update(trader_self_certification: :trader, tos_url: "https://example.com/tos",
                                  third_party_services: "none", repository_visibility: :public,
                                  transparency_disclosure: "Disclosure")
        assert @listing.trader_self_certification.present?
        assert @listing.tos_url.present?
        assert @listing.third_party_services.present?
        refute @listing.repository_unspecified?
        assert @listing.transparency_disclosure.present?
        assert @listing.valid?
      end

      test "is valid if attributes are missing but the listing is still a draft" do
        @draft_listing.update(tos_url: "https://example.com/tos")
        assert @draft_listing.valid?
      end

      test "is invalid if the tos is missing and the listing is for a copilot extension" do
        @copilot_listing.update(tos_url: nil)
        refute @copilot_listing.valid?
        assert_equal "You must add a terms of service URL", @copilot_listing.errors.full_messages.first
      end

      test "is valid if the tos is missing but the listing is not for a copilot extension" do
        @listing.update(tos_url: nil)
        assert @listing.valid?
      end

      test "is invalid if third party services are missing" do
        @listing.update(third_party_services: nil)
        refute @listing.valid?
        assert_equal "You must specify third party services", @listing.errors.full_messages.first
      end

      context "repo visibility" do
        test "is valid if repo visibility is unspecified" do
          @listing.update(repository_visibility: :unspecified)
          assert @listing.valid?
        end

        test "is valid if repo visibility is public" do
          @listing.update(repository_visibility: :public)
          assert @listing.valid?
        end

        test "is valid if repo visibility is private" do
          @listing.update(repository_visibility: :private)
          assert @listing.valid?
        end
      end

      test "is invalid if transparency disclosure is missing and is a high risk ai" do
        @copilot_listing.update(ai_risk_level: :high, transparency_disclosure: nil)
        refute @copilot_listing.valid?
        assert_equal "You must add a transparency disclosure", @copilot_listing.errors.full_messages.first
      end

      test "is valid if transparency disclosure is missing but the listing is not a high risk ai" do
        @listing.update(ai_risk_level: :not_high, transparency_disclosure: nil)
        assert @listing.valid?
      end
    end
  end

  context "#dsa_compliant?" do
    context "when certified as a non-trader" do
      test "is true" do
        @listing.update(trader_self_certification: :non_trader, trader_address: nil, trader_id_type: nil, trader_id: nil)
        assert @listing.dsa_compliant?
      end
    end

    context "when certified as a trader" do
      test "true when all dsa fields are valid" do
        assert @listing.trader_self_certification.present?
        assert @listing.trader_address.present?
        assert @listing.trader_id_type.present?
        assert @listing.trader_id.present?
        assert @listing.has_eu_compliance_attestation.present?
        assert @listing.dsa_compliant?
      end

      test "false when trader_self_certification is missing" do
        @listing.trader_self_certification = nil
        refute @listing.dsa_compliant?
      end

      test "false when trader_address is missing" do
        @listing.trader_address = nil
        refute @listing.dsa_compliant?
      end

      test "false when trader_id_type is missing" do
        @listing.trader_id_type = nil
        refute @listing.dsa_compliant?
      end

      test "false when trader_id is missing" do
        @listing.trader_id = nil
        refute @listing.dsa_compliant?
      end

      test "false when has_eu_compliance_attestation is false" do
        @listing.has_eu_compliance_attestation = false
        refute @listing.dsa_compliant?
      end

      test "false when privacy_policy_url is missing" do
        @listing.privacy_policy_url = nil
        refute @listing.dsa_compliant?
      end
    end

    context "when there is no trader certification" do
      test "is false" do
        @listing.update(trader_self_certification: nil)
        refute @listing.dsa_compliant?
      end
    end
  end

  context "#ai_compliant?" do
    test "is true if the listing has specified the ai_risk_level, llms_in_use, and is_eu_ai_act_compliant" do
      assert @copilot_listing.ai_compliant?
    end

    test "is false if the listing has not specified the ai_risk_level" do
      @copilot_listing.ai_risk_level = :unspecified

      refute @copilot_listing.ai_compliant?
    end

    test "is false if the listing has not specified the llms_in_use" do
      @copilot_listing.llms_in_use = nil

      refute @copilot_listing.ai_compliant?
    end

    test "is false if the listing has false for is_eu_ai_act_compliant" do
      @copilot_listing.is_eu_ai_act_compliant = false

      refute @copilot_listing.ai_compliant?
    end
  end

  context "#security_complete?" do
    test "is true if the listing has specified all attributes" do
      assert @listing.security_complete?
    end

    test "is false if the listing has not specified the privacy_policy_url" do
      @listing.privacy_policy_url = nil

      refute @listing.security_complete?
    end

    test "is false if the listing has not specified the tos_url and is a copilot extension listing" do
      @copilot_listing.tos_url = nil

      refute @copilot_listing.security_complete?
    end

    test "is true if the listing has not specified the tos_url but is not a copilot extension listing" do
      @listing.tos_url = nil

      assert @listing.security_complete?
    end

    test "is false if the listing has not specified third_party_services" do
      @listing.third_party_services = nil

      refute @listing.security_complete?
    end

    test "is false if the listing has has not specified repository_unspecified?" do
      @listing.repository_visibility = :unspecified

      refute @listing.security_complete?
    end

    test "is false if the listing has not specified the transparency_disclosure and is a high-risk ai" do
      @listing.transparency_disclosure = nil
      @listing.ai_risk_level = :high

      refute @listing.security_complete?
    end

    test "is true if the listing has not specified the transparency_disclosure but is not a high-risk ai" do
      @listing.transparency_disclosure = nil
      @listing.ai_risk_level = :not_high

      assert @listing.security_complete?
    end
  end

  context "#security_and_compliance_completed?" do
    context "when the listing is not a copilot app" do
      test "is true if the listing is dsa compliant" do
        assert @listing.security_and_compliance_completed?
      end

      test "is false if the listing is not dsa compliant" do
        refute @noncompliant_listing.security_and_compliance_completed?
      end
    end

    context "when the listing is a copilot app" do
      test "is true if the listing is dsa and ai compliant" do
        assert @copilot_listing.security_and_compliance_completed?
      end

      test "is false if the listing is not dsa compliant" do
        @copilot_listing.trader_address = nil
        refute @copilot_listing.security_and_compliance_completed?
      end

      test "is false if the listing is not ai compliant" do
        @copilot_listing.ai_risk_level = :unspecified

        refute @copilot_listing.security_and_compliance_completed?
      end
    end
  end

  context "#listable_is_copilot_configured?" do
    context "when the listable is not an Integration" do
      test "is false" do
        assert @listing.listable.is_a?(OauthApplication)
        refute @listing.listable_is_copilot_configured?
      end
    end

    context "when the listable is an Integration" do
      test "is true if the integration has configured an agent" do
        assert @copilot_listing.listable_is_copilot_configured?
      end

      test "is false if the integration has not configured an agent" do
        plain_integration_listing = create(:marketplace_listing, :integration)
        refute plain_integration_listing.listable_is_copilot_configured?
      end
    end
  end
end
