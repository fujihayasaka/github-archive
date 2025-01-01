# typed: true
# frozen_string_literal: true

require "test_helper"

class UserRepositoryForkingDependencyTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @business = create(:global_business)
    @owner = create(:user, login: "owner", email: "owner@example.com", plan: "medium")
    @staffer = create(:staff_admin_user, login: "staffer", plan: "medium", email: "staffer@example.com")
    @free_user = create(:user, login: "free-user", email: "free-user@example.com")
    @grit = create(:repository, name: "grit", owner: @free_user, from_example: :pull_request_source)
    @ambition = create(:private_repository, name: "ambition", owner: @staffer)

    @staffer_grit = create(:fork_repository, forker: @staffer, fork_repo: @grit, from_example: :pull_request_fork)
  end

  test "goes to your fork" do
    assert_equal @staffer_grit, @staffer.my_fork_of(@grit)
    assert_equal @grit, @free_user.my_fork_of(@grit)
  end

  context "fork_allowed?" do
    test "returns true for public repositories" do
      assert @free_user.fork_allowed?(@grit)
    end

    test "returns true for private repositories owned by users" do
      assert @free_user.fork_allowed?(@ambition)
    end

    test "return false for private repository owned by enterprise org with forks disabled" do

      @business.allow_private_repository_forking(force: true, actor: @staffer, policy: Configurable::AllowPrivateRepositoryForking::DISABLED)
      business_org = create(:organization, business: @business, admin: @staffer)
      business_private_repo = create(:private_repository, owner: business_org)

      refute @staffer.fork_allowed?(business_private_repo)
    end

    test "return false for private repository owned by enterprise org with a policy that only allows same org forking" do
      @business.allow_private_repository_forking(force: true, actor: @staffer, policy: Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION)

      business_org = create(:organization, business: @business, admin: @staffer)
      business_private_repo = create(:private_repository, owner: business_org)

      refute @staffer.fork_allowed?(business_private_repo)
    end

    test "return false for private repository owned by enterprise org with a policy that only allows enterprise org forking" do
      @business.allow_private_repository_forking(force: true, actor: @staffer, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS)

      business_org = create(:organization, business: @business, admin: @staffer)
      business_private_repo = create(:private_repository, owner: business_org)

      refute @staffer.fork_allowed?(business_private_repo)
    end

    test "return true for private repository owned by enterprise org with a policy that allows forking to user accounts and same org" do
      @business.allow_private_repository_forking(force: true, actor: @staffer, policy: Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION_USER_ACCOUNTS)

      business_org = create(:organization, business: @business, admin: @staffer)
      business_private_repo = create(:private_repository, owner: business_org)

      assert @staffer.fork_allowed?(business_private_repo)
    end

    test "return true for private repository owned by enterprise org with a policy that allows enterprise org and user account forking" do
      @business.allow_private_repository_forking(force: true, actor: @staffer, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

      business_org = create(:organization, business: @business, admin: @staffer)
      business_private_repo = create(:private_repository, owner: business_org)

      assert @staffer.fork_allowed?(business_private_repo)
    end

    test "return true for private repository owned by enterprise org with a policy that allows forking to user accounts" do
      @business.allow_private_repository_forking(force: true, actor: @staffer, policy: Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS)

      business_org = create(:organization, business: @business, admin: @staffer)
      business_private_repo = create(:private_repository, owner: business_org)

      assert @staffer.fork_allowed?(business_private_repo)
    end

    test "return true for private repository owned by enterprise org with a policy that allows forking everywhere" do
      @business.allow_private_repository_forking(force: true, actor: @staffer, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

      business_org = create(:organization, business: @business, admin: @staffer)
      business_private_repo = create(:private_repository, owner: business_org)

      assert @staffer.fork_allowed?(business_private_repo)
    end
  end

end
