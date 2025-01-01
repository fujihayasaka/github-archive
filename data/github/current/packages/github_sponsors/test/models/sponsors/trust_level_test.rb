# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::TrustLevelTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @staff = create(:staff_admin_user)
    @user = create(:user)
  end

  context "#as_sponsor" do
    test "returns :untrusted for account less than 6 months old" do
      @user.created_at = 4.months.ago

      trust_level = Sponsors::TrustLevel.as_sponsor(@user)

      refute_predicate trust_level, :forced?
      assert_predicate trust_level, :untrusted?
      assert_equal "Account fewer than 6 months old.", trust_level.reason
    end

    test "return :neutral for account between 6 months and a year old" do
      @user.update(created_at: 8.months.ago)

      trust_level = Sponsors::TrustLevel.as_sponsor(@user)

      refute_predicate trust_level, :forced?
      assert_predicate trust_level, :neutral?
      assert_equal "Account between 6 and 12 months old.", trust_level.reason
    end

    test "returns :trusted for account more than a year old" do
      @user.update(created_at: 14.months.ago)

      trust_level = Sponsors::TrustLevel.as_sponsor(@user)

      refute_predicate trust_level, :forced?
      assert_predicate trust_level, :trusted?
      assert_equal "Account more than 12 months old.", trust_level.reason
    end

    test "returns :trusted for new account whose trust level has been forced" do
      assert_predicate Sponsors::TrustLevel.as_sponsor(@user), :untrusted?

      Sponsors::TrustLevel.set_as_sponsor(
        actor: @staff,
        sponsor: @user,
        trust_level: Sponsors::TrustLevel::TRUSTED,
      )

      trust_level = Sponsors::TrustLevel.as_sponsor(@user)

      assert_predicate trust_level, :forced?
      assert_predicate trust_level, :trusted?
      assert_equal "Trust level forced.", trust_level.reason
    end
  end

  context "#as_sponsorable" do
    test "returns :untrusted for account less than 6 months old" do
      @user.update(created_at: 4.months.ago)

      trust_level = Sponsors::TrustLevel.as_sponsorable(@user)

      refute_predicate trust_level, :forced?
      assert_predicate trust_level, :untrusted?
      assert_equal "Account fewer than 6 months old.", trust_level.reason
    end

    test "return :neutral for account between 6 months and a year old" do
      @user.update(created_at: 8.months.ago)

      trust_level = Sponsors::TrustLevel.as_sponsorable(@user)

      refute_predicate trust_level, :forced?
      assert_predicate trust_level, :neutral?
      assert_equal "Account between 6 and 12 months old.", trust_level.reason
    end

    test "returns :trusted for account more than a year old" do
      @user.update(created_at: 14.months.ago)

      trust_level = Sponsors::TrustLevel.as_sponsorable(@user)

      refute_predicate trust_level, :forced?
      assert_predicate trust_level, :trusted?
      assert_equal "Account more than 12 months old.", trust_level.reason
    end

    test "returns :trusted for new account whose trust level has been forced" do
      assert_predicate Sponsors::TrustLevel.as_sponsor(@user), :untrusted?

      Sponsors::TrustLevel.set_as_sponsorable(
        actor: @staff,
        sponsorable: @user,
        trust_level: Sponsors::TrustLevel::TRUSTED,
      )

      trust_level = Sponsors::TrustLevel.as_sponsorable(@user.reload)

      assert_predicate trust_level, :forced?
      assert_predicate trust_level, :trusted?
      assert_equal "Trust level forced.", trust_level.reason
    end
  end

  context "#set_as_sponsor" do
    test "updates trust level" do
      new_trust_level = Sponsors::TrustLevel.set_as_sponsor(
        actor: @staff,
        sponsor: @user,
        trust_level: Sponsors::TrustLevel::TRUSTED,
      )

      assert_predicate new_trust_level, :trusted?
      assert_predicate @user.reload.trust_level_as_sponsor, :trusted?
    end

    test "raises error on invalid trust level" do
      invalid_trust_level = :total_nonsense
      error = assert_raises(Sponsors::TrustLevel::UnprocessableError) do
        new_trust_level = Sponsors::TrustLevel.set_as_sponsor(
          actor: @staff,
          sponsor: @user,
          trust_level: invalid_trust_level,
        )
      end

      assert_equal "Could not save trust level #{invalid_trust_level} for sponsor #{@user}", error.message
    end

    test "creates an audit log" do
      expected_payload = {
        staff_actor: @staff.login,
        user: @user.login,
        user_id: @user.id,
        trust_type: "sponsor",
        old_trust_level_forced: false,
        old_trust_level: "untrusted",
        trust_level: "trusted",
        trust_level_forced: true,
      }

      events = assert_performed_audit_entries(count: 1, only: "sponsors.trust_level_manually_set") do
        Sponsors::TrustLevel.set_as_sponsor(
          actor: @staff,
          sponsor: @user,
          trust_level: Sponsors::TrustLevel::TRUSTED,
        )
      end

      assert_subset_hash expected_payload, events.first
      assert_predicate @user.reload.trust_level_as_sponsor, :trusted?
    end

    test "does nothing if actor is not staff" do
      Sponsors::TrustLevel.set_as_sponsor(
        actor: @user,
        sponsor: @user,
        trust_level: Sponsors::TrustLevel::TRUSTED,
      )

      assert_predicate @user.reload.trust_level_as_sponsor, :untrusted?
    end
  end

  context "#set_as_sponsorable" do
    test "updates trust level" do
      new_trust_level = Sponsors::TrustLevel.set_as_sponsorable(
        actor: @staff,
        sponsorable: @user,
        trust_level: Sponsors::TrustLevel::TRUSTED,
      )

      assert_predicate new_trust_level, :trusted?
      assert_predicate @user.reload.trust_level_as_sponsorable, :trusted?
    end

    test "raises error on invalid trust level" do
      invalid_trust_level = :total_nonsense
      error = assert_raises(Sponsors::TrustLevel::UnprocessableError) do
        new_trust_level = Sponsors::TrustLevel.set_as_sponsorable(
          actor: @staff,
          sponsorable: @user,
          trust_level: invalid_trust_level,
        )
      end

      assert_equal "Could not save trust level #{invalid_trust_level} for sponsorable #{@user}", error.message
    end

    test "creates an audit log" do
      expected_payload = {
        staff_actor: @staff.login,
        user: @user.login,
        user_id: @user.id,
        trust_type: "sponsorable",
        old_trust_level_forced: false,
        old_trust_level: "untrusted",
        trust_level: "trusted",
        trust_level_forced: true,
      }

      events = assert_performed_audit_entries(count: 1, only: "sponsors.trust_level_manually_set") do
        Sponsors::TrustLevel.set_as_sponsorable(
          actor: @staff,
          sponsorable: @user,
          trust_level: Sponsors::TrustLevel::TRUSTED,
        )
      end

      assert_subset_hash expected_payload, events.first
      assert_predicate @user.reload.trust_level_as_sponsorable, :trusted?
    end

    test "does nothing if actor is not staff" do
      Sponsors::TrustLevel.set_as_sponsorable(
        actor: @user,
        sponsorable: @user,
        trust_level: Sponsors::TrustLevel::TRUSTED,
      )

      assert_predicate @user.reload.trust_level_as_sponsorable, :untrusted?
    end
  end

  context "Result#new" do
    test "raises on invalid trust level" do
      error = assert_raises RuntimeError do
        Sponsors::TrustLevel::Result.new(:invalid,
          calculated_trust_level: :trusted,
          target_type: :sponsor,
          target: @user,
          forced: false
        )
      end

      assert_equal "Invalid trust level", error.message
    end

    test "raises on invalid calculated trust level" do
      error = assert_raises RuntimeError do
        Sponsors::TrustLevel::Result.new(:trusted,
          calculated_trust_level: :invalid,
          target_type: :sponsor,
          target: @user,
          forced: false
        )
      end

      assert_equal "Invalid calculated trust level", error.message
    end

    test "raises on invalid target_type" do
      error = assert_raises RuntimeError do
        Sponsors::TrustLevel::Result.new(:trusted,
          calculated_trust_level: :trusted,
          target_type: :invalid,
          target: @user,
          forced: false
        )
      end

      assert_equal "Invalid target type", error.message
    end
  end
end if GitHub.sponsors_enabled?
