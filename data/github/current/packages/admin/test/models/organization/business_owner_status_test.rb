# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessOwnerStatusTest < GitHub::TestCase
  context "#error?" do
    test "when is error: return true" do
      assert_predicate Organization::BusinessOwnerStatus.new(:no_2fa), :error?
    end

    test "when is not error: return false" do
      refute_predicate Organization::BusinessOwnerStatus.new(:success_owner), :error?
      refute_predicate Organization::BusinessOwnerStatus.new(:success_member), :error?
      refute_predicate Organization::BusinessOwnerStatus.new(:success_removed), :error?
    end
  end

  context "#sucess?" do
    test "when is succes: return true" do
      assert_predicate Organization::BusinessOwnerStatus.new(:success_owner), :success?
      assert_predicate Organization::BusinessOwnerStatus.new(:success_member), :success?
      assert_predicate Organization::BusinessOwnerStatus.new(:success_removed), :success?
      assert_predicate Organization::BusinessOwnerStatus.new(:no_change), :success?
    end

    test "when is not succes: return false" do
      refute_predicate Organization::BusinessOwnerStatus.new(:no_2fa), :success?
    end
  end

  context "#message" do
    test "when :no_seat, it returns the correct message" do
      assert_equal Organization::BusinessOwnerStatus::MESSAGES[:no_seat], Organization::BusinessOwnerStatus.new(:no_seat).message
    end

    test "when :no_2fa, it returns the correct message" do
      assert_equal(
        Organization::BusinessOwnerStatus::MESSAGES[:no_2fa],
        Organization::BusinessOwnerStatus.new(:no_2fa).message,
      )
    end

    test "when :no_owners, it returns the correct message" do
      assert_equal(
        Organization::BusinessOwnerStatus::MESSAGES[:no_owners],
        Organization::BusinessOwnerStatus.new(:no_owners).message,
      )
    end

    test "when :emu_member_in_external_group, it returns the correct message" do
      assert_equal(
        Organization::BusinessOwnerStatus::MESSAGES[:emu_member_in_external_group],
        Organization::BusinessOwnerStatus.new(:emu_member_in_external_group).message,
      )
    end

    test "when :not_successful, it returns the correct message" do
      assert_equal(
        Organization::BusinessOwnerStatus::MESSAGES[:not_successful],
        Organization::BusinessOwnerStatus.new(:not_successful).message,
      )
    end

    test "when :no_permission, it returns the correct message" do
      assert_equal(
        Organization::BusinessOwnerStatus::MESSAGES[:no_permission],
        Organization::BusinessOwnerStatus.new(:no_permission).message,
      )
    end

    test "when :invalid_user_state, it returns the correct message" do
      assert_equal(
        Organization::BusinessOwnerStatus::MESSAGES[:invalid_user_state],
        Organization::BusinessOwnerStatus.new(:invalid_user_state).message,
      )
    end

    test "when :saml_enforced, it returns the correct message" do
      assert_equal(
        Organization::BusinessOwnerStatus::MESSAGES[:saml_enforced],
        Organization::BusinessOwnerStatus.new(:saml_enforced).message,
      )
    end

    test "when :success, it returns nil" do
      assert_nil(Organization::BusinessOwnerStatus.new(:success_owner).message)
    end
  end
end
