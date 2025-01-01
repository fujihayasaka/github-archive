# typed: strict
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CanRestoreRepositoryTest < GitHub::TestCase
    test "returns true when actor is user" do
      user = create(:user)
      assert user.can_restore_repository?(user)
    end

    test "returns false when actor is not user" do
      user = create(:user)
      user2 = create(:user)
      refute user.can_restore_repository?(user2)
    end

    test "returns true when actor is org admin" do
      user = create(:user)
      org = create(:organization, admin: user)
      assert org.can_restore_repository?(user)
    end

    test "returns false when actor is not org admin" do
      user = create(:user)
      user2 = create(:user)
      org = create(:organization, admin: user)
      org.add_member(user2)
      refute org.can_restore_repository?(user2)
    end
  end
end
