# typed: true
# frozen_string_literal: true

require "test_helper"

class CapLegacyPersonalAccessTokensPolicyTest < GitHub::TestCase
  class FakeEnforcer < ConditionalAccess::Api::Public::Enforcer
    DEFAULT_POLICIES = [
      :legacy_personal_access_tokens
    ]

    def registered_policies
      DEFAULT_POLICIES
    end

    def location
      :test
    end
  end

  class MockCallback
    attr_reader :actor_for_conditional_access

    sig { params(actor_for_conditional_access: T.untyped).void }
    def initialize(actor_for_conditional_access: nil)
      @actor_for_conditional_access = actor_for_conditional_access
    end

    sig { returns(T::Boolean) }
    def logged_in?
      actor_for_conditional_access.present?
    end

    sig { returns(NilClass) }
    def find_repo; end
  end

  fixtures do
    @user = create(:user)
    @org = create :business_plus_org, admin: @user

    @user_pat = create(:oauth_access, :personal_token, user: @user)

    @business = create :business, owners: [@user]
    @business_owned_org = create :business_plus_org, admin: @user
    @business.add_organization(@business_owned_org)
  end

  setup do
    @target_provider = ConditionalAccess::TargetProvider.new(location: :test, callback_name: "test")
  end

  context "#legacy_personal_access_tokens_applicable" do
    test "is not applicable for anonymous requests" do
      callback = MockCallback.new
      policy = FakeEnforcer.new(callback)

      assert_equal :no, policy.legacy_personal_access_tokens_applicable(resource: @org, target_provider: @target_provider)
    end

    test "is not applicable when the actor isn't a User" do
      bot = create(:integration).bot

      callback = MockCallback.new(actor_for_conditional_access: bot)
      policy   = FakeEnforcer.new(callback)

      assert_equal :no, policy.legacy_personal_access_tokens_applicable(resource: @org, target_provider: @target_provider)
    end

    test "is not applicable when the actor isn't using a legacy PAT" do
      @org.restrict_legacy_personal_access_tokens(actor: @user)

      @user.oauth_access = create(:oauth_access, user: @user)
      refute_predicate @user, :using_personal_access_token?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal :no, policy.legacy_personal_access_tokens_applicable(resource: @org, target_provider: @target_provider)
    end

    test "is not applicable when the resource has no target for conditional access" do
      @user.oauth_access = @user_pat
      assert_predicate @user, :using_personal_access_token?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal :no, policy.legacy_personal_access_tokens_applicable(resource: :no_target_for_conditional_access, target_provider: @target_provider)
    end

    test "is not applicable when the resources's TFCA is not an Org or Business" do
      repository = create(:repository, :minimal, owner: @user)
      assert_equal @user, repository.target_for_conditional_access

      @user.oauth_access = @user_pat
      assert_predicate @user, :using_personal_access_token?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal :no, policy.legacy_personal_access_tokens_applicable(resource: repository, target_provider: @target_provider)
    end

    test "is not applicable when the resource's TFCA is an org but the org hasn't restricted legacy PAT access" do
      org_repo = create(:repository, :minimal, owner: @org)
      assert_equal @org, org_repo.target_for_conditional_access

      @user.oauth_access = @user_pat
      assert_predicate @user, :using_personal_access_token?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal :no, policy.legacy_personal_access_tokens_applicable(resource: org_repo, target_provider: @target_provider)
    end

    context "is applicable" do
      test "when the resource's TFCA is an org that has restricted legacy PATs" do
        @org.restrict_legacy_personal_access_tokens(actor: @user)
        org_repo = create(:repository, :minimal, owner: @org)

        @user.oauth_access = @user_pat
        assert_predicate @user, :using_personal_access_token?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.legacy_personal_access_tokens_applicable(resource: org_repo, target_provider: @target_provider)
      end

      test "when the business has restricted legacy PATs" do
        @business.restrict_legacy_personal_access_tokens(actor: @user)

        @user.oauth_access = @user_pat
        assert_predicate @user, :using_personal_access_token?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.legacy_personal_access_tokens_applicable(resource: @business, target_provider: @target_provider)
      end

      test "when the a org's business has restricted legacy PATs for all orgs" do
        @business.restrict_legacy_personal_access_tokens(actor: @user)

        @user.oauth_access = @user_pat
        assert_predicate @user, :using_personal_access_token?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.legacy_personal_access_tokens_applicable(resource: @business_owned_org, target_provider: @target_provider)
      end
    end
  end

  context "#legacy_personal_access_tokens_satisfied" do
    context "is not satisfied" do
      test "when the user is a business member" do
        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.legacy_personal_access_tokens_satisfied(resource: @business, target_provider: @target_provider)
      end

      test "when the user is an org member" do
        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.legacy_personal_access_tokens_satisfied(resource: @org, target_provider: @target_provider)
      end

      test "when the user is an org billing manager" do
        manager = create(:user)
        @org.billing.add_manager(manager, actor: @user)

        callback = MockCallback.new(actor_for_conditional_access: manager)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.legacy_personal_access_tokens_satisfied(resource: @org, target_provider: @target_provider)
      end

      test "when the user is an repo outside collaborator for an org" do
        collaborator = create(:user)
        repository   = create(:repository, :minimal, owner: @org)

        repository.add_member(collaborator)
        refute @org.direct_or_team_member?(collaborator)

        callback = MockCallback.new(actor_for_conditional_access: collaborator)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.legacy_personal_access_tokens_satisfied(resource: repository, target_provider: @target_provider)
      end

      test "when the user is a repo outside collaborator for an org and the resource is an org" do
        collaborator = create(:user)
        repository   = create(:repository, :minimal, owner: @org)

        repository.add_member(collaborator)
        refute @org.direct_or_team_member?(collaborator)

        callback = MockCallback.new(actor_for_conditional_access: collaborator)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.legacy_personal_access_tokens_satisfied(resource: @org, target_provider: @target_provider)
      end
    end
  end

  context "#multiple_legacy_personal_access_tokens_applicable" do
    test "returns nothing for anonymous requests" do
      callback = MockCallback.new
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_legacy_personal_access_tokens_applicable([@org], @target_provider)
    end

    test "returns nothing when the actor isn't a User" do
      bot = create(:integration).bot

      callback = MockCallback.new(actor_for_conditional_access: bot)
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_legacy_personal_access_tokens_applicable([@org], @target_provider)
    end

    test "returns nothing when the actor isn't using a legacy PAT" do
      @org.restrict_legacy_personal_access_tokens(actor: @user)

      @user.oauth_access = create(:oauth_access, user: @user)
      refute_predicate @user, :using_personal_access_token?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_legacy_personal_access_tokens_applicable([@org], target_provider: @target_provider)
    end

    test "returns resources of type Organization or Business" do
      user_repository = create(:repository, :minimal, owner: @user)
      org_repository = create(:repository, :minimal, owner: @org)

      @user.oauth_access = @user_pat
      assert_predicate @user, :using_personal_access_token?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      applicable = policy.multiple_legacy_personal_access_tokens_applicable([
        :no_target_for_conditional_access, user_repository, org_repository, @business, @org
      ], @target_provider)

      assert_same_elements [@business, @org], applicable
    end
  end

  context "#multiple_legacy_personal_access_tokens_satisfied" do
    test "returns orgs where the user is a member and are not directly restricted" do
      @org.restrict_legacy_personal_access_tokens(actor: @user)
      other_org = create(:organization, admin: @user)

      @user.oauth_access = @user_pat
      assert_predicate @user, :using_personal_access_token?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal({ @org => { private: :unsatisfied }, other_org => { private: :satisfied } }, policy.multiple_legacy_personal_access_tokens_satisfied([
        @org, other_org
      ], @target_provider))
    end

    test "return unsatisfied orgs where the owning business has restricted access" do
      @business.restrict_legacy_personal_access_tokens(actor: @user)

      @user.oauth_access = @user_pat
      assert_predicate @user, :using_personal_access_token?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal({ @business_owned_org => { private: :unsatisfied } }, policy.multiple_legacy_personal_access_tokens_satisfied([@business_owned_org], @target_provider))
    end

    test "return unsatisfied businesses that restrict access" do
      @business.restrict_legacy_personal_access_tokens(actor: @user)

      @user.oauth_access = @user_pat
      assert_predicate @user, :using_personal_access_token?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal({ @business => { private: :unsatisfied } }, policy.multiple_legacy_personal_access_tokens_satisfied([@business], @target_provider))
    end
  end
end
