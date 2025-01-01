# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd::Publishing
  class ActorValidationTest < GitHub::TestCase

    test "does not validate nil", skip_enterprise: true do
      validation = Notifyd::Publishing::ActorValidation.new(actor: nil).validate

      refute validation.valid?
      assert validation.invalid?
      assert_equal :invalid, validation.status
      assert_equal "nil", validation.reason
    end

    test "does not validate spammy users", skip_enterprise: true do
      validation = Notifyd::Publishing::ActorValidation.new(actor: build(:spammy_user)).validate

      refute validation.valid?
      assert validation.invalid?
      assert_equal :invalid, validation.status
      assert_equal "spammy", validation.reason
    end

    test "does not validate suspended users", skip_enterprise: true do
      validation = Notifyd::Publishing::ActorValidation.new(actor: build(:suspended_user)).validate

      refute validation.valid?
      assert validation.invalid?
      assert_equal :invalid, validation.status
      assert_equal "suspended", validation.reason
    end

    test "validates standard user", skip_enterprise: true do
      validation = Notifyd::Publishing::ActorValidation.new(actor: build(:user)).validate

      refute validation.invalid?
      assert validation.valid?
      assert_equal :valid, validation.status
      assert_equal "none", validation.reason
    end
  end
end
