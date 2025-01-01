# typed: true
# frozen_string_literal: true

require "test_helper"

class CapPersonalAccessTokensPolicyTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers

  class FakeEnforcer < ConditionalAccess::Api::Public::Enforcer # Use an existing enforcer to make Sorbet happy.
    DEFAULT_POLICIES = [
      :personal_access_tokens
    ]

    def registered_policies
      DEFAULT_POLICIES
    end

    def location
      :test
    end
  end

  class MockCallback
    extend T::Sig

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

    @business = create :business, owners: [@user]
    @business_owned_org = create :business_plus_org, admin: @user
    @business.add_organization(@business_owned_org)
  end

  setup do
    @target_provider = ConditionalAccess::TargetProvider.new(location: :test, callback_name: "test")
  end

  def create_pat_for_user(on: @org)
    @user.programmatic_access = make_user_programmatic_access_with_grant(
      requester: @user, target: on,
    )
  end

  context "#personal_access_tokens_applicable" do
    test "is not applicable for anonymous requests" do
      callback = MockCallback.new
      policy   = FakeEnforcer.new(callback)

      assert_predicate policy, :anonymous?
      assert_equal :no, policy.personal_access_tokens_applicable(resource: @org, target_provider: @target_provider)
    end

    test "is not applicable when the actor isn't a User" do
      bot = create(:integration).bot

      callback = MockCallback.new(actor_for_conditional_access: bot)
      policy   = FakeEnforcer.new(callback)

      assert_equal :no, policy.personal_access_tokens_applicable(resource: @org, target_provider: @target_provider)
    end

    test "is not applicable when the actor isn't using a PAT" do
      refute_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal :no, policy.personal_access_tokens_applicable(resource: @org, target_provider: @target_provider)
    end

    test "is not applicable when the resource has no target for conditional access" do
      create_pat_for_user(on: @org)

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal :no, policy.personal_access_tokens_applicable(resource: :no_target_for_conditional_access, target_provider: @target_provider)
    end

    test "is not applicable when the resources's TFCA is not an Org or Business" do
      create_pat_for_user(on: @user)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal :no, policy.personal_access_tokens_applicable(resource: @user, target_provider: @target_provider)
    end

    test "is not applicable when the resource's TFCA is an org that allows PAT access" do
      @org.permit_personal_access_tokens(actor: @user)
      create_pat_for_user(on: @user)

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal :no, policy.personal_access_tokens_applicable(resource: @org, target_provider: @target_provider)
    end

    context "is applicable" do
      test "when the resource's TFCA is an org that does not allow PATs" do
        create_pat_for_user(on: @org)
        @org.restrict_personal_access_tokens(actor: @user)
        assert_predicate @org, :personal_access_tokens_restricted?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.personal_access_tokens_applicable(resource: @org, target_provider: @target_provider)
      end

      test "when the business does not allow PATs" do
        create_pat_for_user(on: @business_owned_org)
        @business.restrict_personal_access_tokens(actor: @user)
        assert_predicate @business, :personal_access_tokens_restricted?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.personal_access_tokens_applicable(resource: @business, target_provider: @target_provider)
      end

      test "when the org's business has restricted PATs for all orgs" do
        assert_predicate @business, :personal_access_tokens_delegated_policy?
        @business_owned_org.permit_personal_access_tokens(actor: @user)

        @business.restrict_personal_access_tokens(actor: @user)
        @business_owned_org.reload # avoid memoization

        create_pat_for_user(on: @business_owned_org)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.personal_access_tokens_applicable(resource: @business_owned_org, target_provider: @target_provider)
      end
    end
  end

  context "#personal_access_tokens_satisfied" do
    context "is not satisfied" do
      test "when target is a business and the actor is a member" do
        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.personal_access_tokens_satisfied(resource: @business, target_provider: @target_provider)
      end

      test "when target is an org and the actor is a member" do
        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.personal_access_tokens_satisfied(resource: @org, target_provider: @target_provider)
      end

      test "when the user is an org billing manager" do
        manager = create(:user)
        @org.billing.add_manager(manager, actor: @user)

        callback = MockCallback.new(actor_for_conditional_access: manager)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.personal_access_tokens_satisfied(resource: @org, target_provider: @target_provider)
      end

      test "when the user is a repo outside collaborator for an org" do
        collaborator = create(:user)
        repository   = create(:repository, :minimal, owner: @org)

        repository.add_member(collaborator)
        refute @org.direct_or_team_member?(collaborator)

        callback = MockCallback.new(actor_for_conditional_access: collaborator)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.personal_access_tokens_satisfied(resource: repository, target_provider: @target_provider)
      end

      test "when the user is a repo outside collaborator for an org and the resource is an org" do
        collaborator = create(:user)
        repository   = create(:repository, :minimal, owner: @org)

        repository.add_member(collaborator)
        refute @org.direct_or_team_member?(collaborator)

        callback = MockCallback.new(actor_for_conditional_access: collaborator)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.personal_access_tokens_satisfied(resource: @org, target_provider: @target_provider)
      end
    end

    context "is satisfied" do
      test "when target is a business and the actor is not a member" do
        not_a_biz_member = create(:user)

        callback = MockCallback.new(actor_for_conditional_access: not_a_biz_member)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.personal_access_tokens_satisfied(resource: @business, target_provider: @target_provider)
      end

      test "when target is an org and the actor is not a member" do
        not_a_member = create(:user)

        callback = MockCallback.new(actor_for_conditional_access: not_a_member)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.personal_access_tokens_satisfied(resource: @org, target_provider: @target_provider)
      end
    end
  end

  context "#multiple_personal_access_tokens_applicable" do
    test "returns nothing for anonymous requests" do
      callback = MockCallback.new
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_personal_access_tokens_applicable([@org], @target_provider)
    end

    test "returns nothing when the actor isn't a User" do
      bot = create(:integration).bot

      callback = MockCallback.new(actor_for_conditional_access: bot)
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_personal_access_tokens_applicable([@org], @target_provider)
    end

    test "returns nothing when the actor isn't using a PAT" do
      refute_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_personal_access_tokens_applicable([@org], target_provider: @target_provider)
    end

    test "returns resources of type Organization or Business" do
      user_repository = create(:repository, :minimal, owner: @user)
      org_repository = create(:repository, :minimal, owner: @org)

      create_pat_for_user(on: @org)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      applicable = policy.multiple_personal_access_tokens_applicable(
        [:no_target_for_conditional_access, user_repository, org_repository, @business, @org],
        @target_provider
      )

      assert_same_elements [@business, @org], applicable
    end
  end

  context "#multiple_personal_access_tokens_satisfied" do
    test "raises when one of the targets has an invalid type" do
      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_raises(ArgumentError) do
        policy.multiple_personal_access_tokens_satisfied([@user], @target_provider)
      end
    end

    test "returns orgs where the user is a member and are not directly restricted" do
      org_allowing_pat = create(:organization, admin: @user)
      org_allowing_pat.permit_personal_access_tokens(actor: @user)
      assert_predicate org_allowing_pat, :personal_access_tokens_allowed?

      @org.restrict_personal_access_tokens(actor: @user)
      assert_predicate @org, :personal_access_tokens_restricted?

      create_pat_for_user(on: @org)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_same_elements [org_allowing_pat], policy.multiple_personal_access_tokens_satisfied(
        [@org, org_allowing_pat],
        @target_provider
      )
    end

    test "returns businesses where the user is a member and PATs are not restricted" do
      @business.permit_personal_access_tokens(actor: @user)

      create_pat_for_user(on: @business_owned_org)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_same_elements [@business], policy.multiple_personal_access_tokens_satisfied([@business], @target_provider)
    end

    test "skips businesses where the user is a member but PATs are restricted" do
      @business.restrict_personal_access_tokens(actor: @user)

      create_pat_for_user(on: @business_owned_org)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_personal_access_tokens_satisfied([@business], @target_provider)
    end

    test "does not return orgs where the owning business has restricted access" do
      @business.restrict_personal_access_tokens(actor: @user)

      create_pat_for_user(on: @business_owned_org)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_personal_access_tokens_satisfied([@business_owned_org], @target_provider)
    end

    test "returns orgs that allow PATs and belong to business without restriction" do
      @business_owned_org.permit_personal_access_tokens(actor: @user)

      create_pat_for_user(on: @business_owned_org)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_same_elements [@business_owned_org], policy.multiple_personal_access_tokens_satisfied(
        [@business_owned_org],
        @target_provider
      )
    end

    test "skips orgs that allow PATs but belong to opted out business" do
      @business_owned_org.permit_personal_access_tokens(actor: @user)
      @business.restrict_personal_access_tokens(actor: @user)

      create_pat_for_user(on: @business_owned_org)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_personal_access_tokens_satisfied([@business_owned_org], @target_provider)
    end

    test "does not return businesses that restrict access" do
      @business.restrict_personal_access_tokens(actor: @user)

      create_pat_for_user(on: @business_owned_org)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_personal_access_tokens_satisfied([@business], @target_provider)
    end
  end
end
