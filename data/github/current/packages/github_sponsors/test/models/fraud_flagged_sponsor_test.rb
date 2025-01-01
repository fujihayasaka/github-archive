# typed: true
# frozen_string_literal: true

require "test_helper"

class FraudFlaggedSponsorTest < GitHub::TestCase
  include HydroTestHelpers

  if GitHub.sponsors_enabled?
    context "validations" do
      test "requires fraud review" do
        flagged = build(:fraud_flagged_sponsor, sponsors_fraud_review: nil)
        refute_predicate flagged, :valid?
      end

      test "requires sponsor" do
        flagged = build(:fraud_flagged_sponsor, sponsor: nil)
        refute_predicate flagged, :valid?
      end

      test "still valid if sponsor deletes their account" do
        flagged = build(:fraud_flagged_sponsor)
        flagged.sponsor.destroy!
        assert_predicate flagged, :valid?
      end

      test "requires at least one matched field" do
        flagged = build(:fraud_flagged_sponsor, matched_current_ip: nil)
        refute_predicate flagged, :valid?
        assert_equal "Must have at least one matched field", flagged.errors.full_messages.to_sentence
      end

      test "sponsor can only be flagged once per fraud review" do
        existing = create(:fraud_flagged_sponsor)
        flagged = build(:fraud_flagged_sponsor,
          sponsors_fraud_review: existing.sponsors_fraud_review,
          sponsor: existing.sponsor,
        )

        refute_predicate flagged, :valid?
      end
    end

    test "instruments hydro event on creation" do
      flagged = create(:fraud_flagged_sponsor)

      expected_message = {
        fraud_review: Hydro::EntitySerializer.sponsors_fraud_review(flagged.sponsors_fraud_review),
        listing: Hydro::EntitySerializer.sponsors_listing(flagged.sponsors_fraud_review.sponsors_listing),
        sponsorable: Hydro::EntitySerializer.user(flagged.sponsors_fraud_review.sponsors_listing.sponsorable),
        sponsor: Hydro::EntitySerializer.user(flagged.sponsor),
        matched_current_client_id: flagged.matched_current_client_id,
        matched_current_ip: flagged.matched_current_ip,
        matched_historical_ip: flagged.matched_historical_ip,
        matched_historical_client_id: flagged.matched_historical_client_id,
        matched_current_ip_region_and_user_agent: flagged.matched_current_ip_region_and_user_agent,
      }

      assert_hydro_published(expected_message, schema: "github.sponsors.v0.SponsorFraudFlagged")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v0.SponsorFraudFlagged")
    end

    test "instruments hydro event when entry is updated" do
      flagged = create(:fraud_flagged_sponsor)
      client_id = "abc123.def456"
      flagged.update!(matched_historical_client_id: client_id)

      expected_message = {
        fraud_review: Hydro::EntitySerializer.sponsors_fraud_review(flagged.sponsors_fraud_review),
        listing: Hydro::EntitySerializer.sponsors_listing(flagged.sponsors_fraud_review.sponsors_listing),
        sponsorable: Hydro::EntitySerializer.user(flagged.sponsors_fraud_review.sponsors_listing.sponsorable),
        sponsor: Hydro::EntitySerializer.user(flagged.sponsor),
        matched_current_client_id: flagged.matched_current_client_id,
        matched_current_ip: flagged.matched_current_ip,
        matched_historical_ip: flagged.matched_historical_ip,
        matched_historical_client_id: client_id,
        matched_current_ip_region_and_user_agent: flagged.matched_current_ip_region_and_user_agent,
      }

      assert_hydro_published(expected_message, schema: "github.sponsors.v0.SponsorFraudFlagged")
      assert_hydro_messages(count: 2, schema: "github.sponsors.v0.SponsorFraudFlagged")
    end
  end
end
