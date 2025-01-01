# typed: true
# frozen_string_literal: true

require "test_helper"

class TrustedRepositoryAuthorizationTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @user_owned_repo = create(:private_repository, owner: @user)
    @external_private_repo = create(:private_repository)
  end

  context "#repository_is_trustable?" do
    test "record is valid when repository is readable by user" do
      record = Codespaces::TrustedRepositoryAuthorization.new(
        user: @user,
        repository: @user_owned_repo
      )

      record.validate

      refute record.errors[:repository].any?
      refute record.errors[:repository].include?("is not readable by user")
    end

    test "record is invalid when repository is not readable by user" do
      record = Codespaces::TrustedRepositoryAuthorization.new(
        user: @user,
        repository: @external_private_repo
      )

      record.validate

      assert record.errors[:repository].any?
      assert record.errors[:repository].include?("is not readable by user")
    end
  end
end unless GitHub.enterprise?
