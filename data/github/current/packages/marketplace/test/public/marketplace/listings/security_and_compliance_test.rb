# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Listings::SecurityAndComplianceTest < GitHub::TestCase
  fixtures do
    @compliant_listing = create(:marketplace_listing, :dsa_compliant)
    @noncompliant_listing = create(:marketplace_listing, privacy_policy_url: nil)
  end

  context "dsa validations" do
    test "does not run validations if not saving a change to a dsa attribute" do
      @noncompliant_listing.update(name: "New name")
      assert @noncompliant_listing.valid?
      assert @noncompliant_listing.errors.empty?
    end

    context "when certifying as a trader" do
      test "is invalid if there is no business address" do
        @noncompliant_listing.update(trader_self_certification: :trader, trader_id_type: "duns", trader_id: "1234ABCD",
                                     has_eu_compliance_attestation: true)
        refute @noncompliant_listing.valid?
        assert_equal "Business address is required", @noncompliant_listing.errors.full_messages.first
      end

      test "is invalid if there is no business id type" do
        @noncompliant_listing.update(trader_self_certification: :trader, trader_address: "1234 Main St",
                                     trader_id: "1234ABCD", has_eu_compliance_attestation: true)
        refute @noncompliant_listing.valid?
        assert_equal "Business id type is required", @noncompliant_listing.errors.full_messages.first
      end

      test "is invalid if there is no business id" do
        @noncompliant_listing.update(trader_self_certification: :trader, trader_address: "1234 Main St",
                                     trader_id_type: "duns", has_eu_compliance_attestation: true)
        refute @noncompliant_listing.valid?
        assert_equal "Business id is required", @noncompliant_listing.errors.full_messages.first
      end
    end
  end

  context "#dsa_compliant?" do
    context "when certified as a non-trader" do
      test "is true" do
        @noncompliant_listing.update(trader_self_certification: :non_trader)
        assert @noncompliant_listing.dsa_compliant?
      end
    end

    context "when certified as a trader" do
      test "true when all dsa fields are valid" do
        assert @compliant_listing.dsa_compliant?
      end

      test "false when trader_self_certification is missing" do
        @compliant_listing.trader_self_certification = nil
        refute @compliant_listing.dsa_compliant?
      end

      test "false when trader_address is missing" do
        @compliant_listing.trader_address = nil
        refute @compliant_listing.dsa_compliant?
      end

      test "false when trader_id_type is missing" do
        @compliant_listing.trader_id_type = nil
        refute @compliant_listing.dsa_compliant?
      end

      test "false when trader_id is missing" do
        @compliant_listing.trader_id = nil
        refute @compliant_listing.dsa_compliant?
      end

      test "false when has_eu_compliance_attestation is false" do
        @compliant_listing.has_eu_compliance_attestation = false
        refute @compliant_listing.dsa_compliant?
      end

      test "false when tos_url is missing" do
        @compliant_listing.tos_url = nil
        refute @compliant_listing.dsa_compliant?
      end

      test "false when privacy_policy_url is missing" do
        @compliant_listing.privacy_policy_url = nil
        refute @compliant_listing.dsa_compliant?
      end
    end

    context "when there is no trader certification" do
      test "is false" do
        @compliant_listing.update(trader_self_certification: nil)
        refute @compliant_listing.dsa_compliant?
      end
    end
  end
end
