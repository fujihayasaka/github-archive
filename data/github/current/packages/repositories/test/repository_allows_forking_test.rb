# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryAllowsForkingTest < GitHub::TestCase
  fixtures do
    @public_repo = create(:repository)
    @private_repo = create(:private_repository)

    @org = create(:organization)
    @public_org_repo = create(:repository, owner: @org)
    @private_org_repo = create :private_repository, owner: @org
  end

  test "is true for public repos" do
    assert_predicate @public_repo, :allows_forking?
  end

  test "is true for private repos configured to allow forking" do
    @private_repo.expects(:allow_private_repository_forking?).returns(true)
    assert_predicate @private_repo, :allows_forking?
  end

  test "is false for private repos configured to NOT allow forking" do
    @private_repo.expects(:allow_private_repository_forking?).returns(false)
    refute_predicate @private_repo, :allows_forking?
  end
end
