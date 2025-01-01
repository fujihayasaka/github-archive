# typed: strict
# frozen_string_literal: true

require "test_helper"

class CanCreateRepositoryTest < GitHub::TestCase
  if GitHub.email_verification_enabled?
    test "verified user can create a repo for herself" do
      user = create :verified_user
      user.stubs(:content_creation_requires_email_verification).returns(true)
      assert user.can_create_repository?(user)
    end
  end

  if GitHub.enterprise?
    test "user can create public repos in GHES instance" do
      user = create :user
      assert user.can_create_repository?(user, visibility: "public")
    end
  else
    test "user can create public repos on dotcom" do
      user = create :user
      assert user.can_create_repository?(user, visibility: "public")
    end
  end
end
