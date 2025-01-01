# typed: true
# frozen_string_literal: true

require "test_helper"

# Remove test suite after orphaned repos issue is resolved.
# See https://github.com/github/github/issues/130381.
class RepositoryOwnerValidationTest < GitHub::TestCase
  fixtures do
    @non_existent_owner_id = 123456
  end

  test "valid when owner is a User" do
    owner = create(:user)
    repo = create(:repository, owner_id: owner.id)
    assert repo.valid?(:owner)
  end

  test "valid when owner is an Organization" do
    owner = create(:organization)
    repo = create(:repository, owner_id: owner.id)
    assert repo.valid?(:owner)
  end
end
