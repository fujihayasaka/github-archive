# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamAddMemberStatusTest < GitHub::TestCase
  def subject
    Team::AddMemberStatus
  end

  context "#error?" do
    test "when is error: return true" do
      assert_predicate subject.new(:blocked), :error?
    end

    test "when is not error: return false" do
      refute_predicate subject.new(:success), :error?
    end
  end

  context "#success?" do
    test "when is success: return true" do
      assert_predicate subject.new(:success), :success?
    end

    test "when is not success: return false" do
      refute_predicate subject.new(:blocked), :success?
    end
  end

  context "#message" do
    test "when :blocked, it returns the correct message" do
      assert_equal Team::AddMemberStatus::MESSAGES[:blocked], subject.new(:blocked).message
    end

    test "when :no_seat, it returns the correct message" do
      assert_equal Team::AddMemberStatus::MESSAGES[:no_seat], subject.new(:no_seat).message
    end

    test "when :no_2fa, it returns the correct message" do
      assert_equal(
        Team::AddMemberStatus::MESSAGES[:no_2fa],
        subject.new(:no_2fa).message,
      )
    end

    test "when :no_saml_sso, it returns the correct message" do
      assert_equal(
        Team::AddMemberStatus::MESSAGES[:no_saml_sso],
        subject.new(:no_saml_sso).message,
      )
    end

    test "when :dupe, it returns the correct message" do
      assert_equal(
        Team::AddMemberStatus::MESSAGES[:dupe],
        subject.new(:dupe).message,
      )
    end

    test "when :pending_cycle_no_seat, it returns the correct message" do
      assert_equal(
        Team::AddMemberStatus::MESSAGES[:pending_cycle_no_seat],
        subject.new(:pending_cycle_no_seat).message,
      )
    end

    test "when :no_permission, it returns the correct message" do
      assert_equal(
        Team::AddMemberStatus::MESSAGES[:no_permission],
        subject.new(:no_permission).message,
      )
    end

    test "when :not_user, it returns the correct message" do
      assert_equal(
        Team::AddMemberStatus::MESSAGES[:not_user],
        subject.new(:not_user).message,
      )
    end

    test "when :trade_controls_restricted, it returns the correct message" do
      assert_equal(
        Team::AddMemberStatus::MESSAGES[:trade_controls_restricted],
        subject.new(:trade_controls_restricted).message,
      )
    end

    test "when :not_array, it returns the correct message" do
      assert_equal(
        Team::AddMemberStatus::MESSAGES[:not_array],
        subject.new(:not_array).message,
      )
    end

    test "when :org_flagged_spammy, it returns the correct message" do
      assert_equal \
        Team::AddMemberStatus::MESSAGES[:org_flagged_spammy],
        subject.new(:org_flagged_spammy).message
    end

    test "when :rate_limit_exceeded, it returns the correct message" do
      assert_equal \
        Team::AddMemberStatus::MESSAGES[:rate_limit_exceeded],
        subject.new(:rate_limit_exceeded).message
    end

    test "when :success, it returns nil" do
      assert_nil(subject.new(:success).message)
    end
  end
end
