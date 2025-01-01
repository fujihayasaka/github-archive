# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryVisibilityTest < GitHub::TestCase

  fixtures do
    @business_org_admin = create(:user)
    @business_org = create(:organization, plan: GitHub::Plan.business_plus, admins: [@business_org_admin])
    @business = create(:business, name: "Ian, Inc", owners: [@business_org_admin], organizations: [@business_org], seats: 20)
    @org = create(:organization, plan: GitHub::Plan.business_plus, admins: [@business_org_admin])
  end

  test "creates new repos with correct visibility" do
    [:private, :public, :internal].each do |visibility|
      repo = create(:private_repository, owner: @business_org)
      assert_equal repo.set_permission(visibility), visibility != :private
      assert_equal visibility, repo.visibility.to_sym
    end
  end

  test "loaded repos have correct visibility" do
    [:private, :public, :internal].each do |visibility|
      repo = create(:private_repository, owner: @business_org)
      assert_equal repo.set_permission(visibility), visibility != :private
      assert_equal visibility, repo.visibility.to_sym

      loaded_repo = Repository.last
      assert_equal repo.visibility, T.must(loaded_repo).visibility
    end
  end

  test "no-op visibility changes are correctly identified" do
    # public -> public
    repo = create(:public_repository, owner: @business_org)
    assert_predicate repo, :public?

    refute repo.set_permission(:public)
    repo.reload
    assert_equal :public, repo.visibility.to_sym
    assert_predicate repo, :public?

    # private -> private
    repo = create(:private_repository, owner: @business_org)
    refute_predicate repo, :public?

    refute repo.set_permission(:private)
    repo.reload
    assert_equal :private, repo.visibility.to_sym
    refute_predicate repo, :public?

    # internal -> internal
    assert repo.set_permission(:internal)
    repo.reload
    assert_equal :internal, repo.visibility.to_sym
    refute repo.set_permission(:internal)
    repo.reload
    assert_equal :internal, repo.visibility.to_sym
    refute repo.public?
  end

  test "visibility correctly changes from public to private" do
    repo = create(:public_repository, owner: @business_org)
    assert repo.set_permission(:private)
    assert_equal :private, repo.visibility.to_sym
    refute repo.public?
  end

  test "visibility correctly changes from public to internal" do
    repo = create(:public_repository, owner: @business_org)
    assert repo.set_permission(:internal)
    assert_equal :internal, repo.visibility.to_sym
    refute repo.public?
  end

  test "visibility correctly changes from internal to private" do
    repo = create(:private_repository, owner: @business_org)
    assert repo.set_permission(:internal)
    assert_equal :internal, repo.visibility.to_sym

    assert repo.set_permission(:private)
    repo.reload
    assert_equal :private, repo.visibility.to_sym
    refute repo.public?
  end

  test "visibility correctly changes from internal to public" do
    repo = create(:private_repository, owner: @business_org)
    repo.set_permission(:internal)
    assert_equal :internal, repo.visibility.to_sym

    assert repo.set_permission(:public)
    repo.reload
    assert_equal :public, repo.visibility.to_sym
    assert_predicate repo, :public?
  end

  test "internal visibility fails with error for personal repositories" do
    repo = create(:private_repository, owner: @business_org_admin)
    e = assert_raises(ArgumentError) { repo.set_permission(:internal) }
    assert e.message.include?("Only organization-owned repositories can have internal visibility")
  end

  test "internal visibility fails with repositories owned by organizations having no business" do
    repo = create(:private_repository, owner: @org)
    e = assert_raises(ArgumentError) { repo.set_permission(:internal) }
    assert e.message.include?("Only organizations associated with an enterprise can set visibility to internal")
  end
end
