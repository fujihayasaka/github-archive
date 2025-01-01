# typed: true
# frozen_string_literal: true

require "test_helper"

class TestPersonalAccessTokensResource
  def initialize(
    target: nil,
    actor_ip: nil,
    repository: nil,
    action: nil,
    actor: nil,
    public_key: nil
  )
    @target = target
    @actor_ip = actor_ip
    @repository = repository
    @action = action
    @actor = actor
    @public_key = public_key
  end

  def target_for_conditional_access
    @target || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def target
    @target
  end

  def actor_ip
    @actor_ip
  end

  def repository
    @repository
  end

  def action
    @action
  end

  def actor
    @actor
  end

  def public_key
    @public_key
  end

  def anonymous?
    !@actor
  end
end

class TestPersonalAccessTokensAuthzdEnforcer < ::ConditionalAccess::AuthzdEnforcer
  include ::ConditionalAccess::Policy::PersonalAccessTokens

  def conditional_access_policies
    [:personal_access_tokens]
  end
  alias :registered_policies :conditional_access_policies

  def location
    :test
  end

  def actor
    callback.send(:actor)
  end

  def actor_ip
    callback.send(:actor_ip)
  end

  def repository
    callback.send(:repository)
  end

  def action
    callback.send(:action)
  end

  def authzd_cap_actor
    actor
  end

  def authzd_cap_request_attributes
    attrs = {}

    if actor_ip
      attrs["conditional.access.ip"] = actor_ip
    end

    if repository
      attrs["conditional.access.repository_id"] = repository.id
    end

    if action
      attrs["conditional.access.action"] = action
    end

    attrs
  end
end

class TestPersonalAccessTokensEnforcer < ::ConditionalAccess::Enforcer
  include ::ConditionalAccess::Policy::PersonalAccessTokens

  def conditional_access_policies
    [:personal_access_tokens]
  end
  alias :registered_policies :conditional_access_policies

  def location
    :test
  end

  def actor
    callback.send(:actor)
  end

  def actor_ip
    callback.send(:actor_ip)
  end

  def repository
    callback.send(:repository)
  end

  def action
    callback.send(:action)
  end

  def anonymous?
    callback.send(:anonymous?)
  end
end

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
    attr_reader :actor_for_conditional_access

    sig { params(actor_for_conditional_access: T.untyped).void }
    def initialize(actor_for_conditional_access: nil)
      @actor_for_conditional_access = actor_for_conditional_access
    end

    sig { returns(T::Boolean) }
    def logged_in?
      actor_for_conditional_access.present?
    end

    def actor
      @actor_for_conditional_access
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

    @org.restrict_personal_access_tokens(actor: @user)
    @business.restrict_personal_access_tokens(actor: @user)

    @integration = create :integration, default_permissions: { Business::Resources.subject_types.first => :read }
    @integration_bot = @integration.bot
    @org_install = make_integration_installation target: @org, integration: @integration
  end

  setup do
    @target_provider = ::ConditionalAccess::TargetProvider.new(location: :test, callback_name: "test")
  end

  def assert_result(resource, result)
    enforcer = ENV["TEST_CAP_VIA_AUTHZD"] ? TestPersonalAccessTokensAuthzdEnforcer.new(resource) : TestPersonalAccessTokensEnforcer.new(resource)
    applied_in = T.type_alias(T.any(TestPersonalAccessTokensAuthzdEnforcer, TestPersonalAccessTokensEnforcer))
    ConditionalAccess::Policy::PersonalAccessTokens.stub_const(:AppliedIn, applied_in) do
      results = enforcer.evaluate_conditional_access_policies resource
      assert_equal 1, results.size
      assert_equal :personal_access_tokens, results.keys.first
      assert_equal result, results.values.first
    end
  end

  def assert_satisfied(resource)
    assert_result(resource, :satisfied)
  end

  def assert_unsatisfied(resource)
    assert_result(resource, :unsatisfied)
  end

  def assert_inapplicable(resource)
    assert_result(resource, :inapplicable)
  end

  def create_pat_for_user(user: @user, on: @org)
    user.programmatic_access = make_user_programmatic_access_with_grant(
      requester: user, target: on,
    )
  end

  def create_pat_for_user_on_restricted_org(user: @user, on: @org)
    on.permit_personal_access_tokens(actor: user)
    create_pat_for_user(user: user, on: on)
    on.restrict_personal_access_tokens(actor: user)
  end

  def create_pat_for_user_on_restricted_business_org(user: @user, on: @business_owned_org)
    business = on.business
    business.reset_personal_access_tokens_restriction(actor: user)
    business.reload

    on.permit_personal_access_tokens(actor: @user)
    on.reload

    create_pat_for_user_on_restricted_org(on: on)

    business.restrict_personal_access_tokens(actor: @user)
  end

  context "#personal_access_tokens_applicable" do
    test "is not applicable for anonymous requests" do
      resource = TestPersonalAccessTokensResource.new(target: @org)
      assert_predicate resource, :anonymous?

      assert_inapplicable resource
    end

    test "is not applicable when the actor isn't a User" do
      @integration_bot.installation = @org_install

      resource = TestPersonalAccessTokensResource.new(target: @org, actor: @integration_bot)
      assert_inapplicable resource
    end

    test "is not applicable when the actor isn't using a PAT" do
      refute_predicate @user, :using_auth_via_user_programmatic_access?

      resource = TestPersonalAccessTokensResource.new(target: @org, actor: @user)
      assert_inapplicable resource
    end

    test "is not applicable when the resource has no target for conditional access" do
      create_pat_for_user_on_restricted_org(on: @org)

      resource = TestPersonalAccessTokensResource.new(target: :no_target_for_conditional_access, actor: @user)
      assert_inapplicable resource
    end

    test "is not applicable when the resources's TFCA is not an Org or Business" do
      create_pat_for_user(on: @user)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      resource = TestPersonalAccessTokensResource.new(target: @user, actor: @user)
      assert_inapplicable resource
    end

    test "is not applicable when the resource's TFCA is an org that allows PAT access" do
      @org.permit_personal_access_tokens(actor: @user)
      create_pat_for_user(on: @user)

      resource = TestPersonalAccessTokensResource.new(target: @org, actor: @user)
      assert_inapplicable resource
    end

    context "is applicable" do
      test "when the resource's TFCA is an org that does not allow PATs" do
        create_pat_for_user_on_restricted_org(on: @org)
        @org.restrict_personal_access_tokens(actor: @user)
        assert_predicate @org, :personal_access_tokens_restricted?

        resource = TestPersonalAccessTokensResource.new(target: @org, actor: @user)
        assert_unsatisfied resource
      end

      test "when the business does not allow PATs" do
        create_pat_for_user_on_restricted_business_org(on: @business_owned_org)
        assert_predicate @business, :personal_access_tokens_restricted?

        resource = TestPersonalAccessTokensResource.new(target: @business, actor: @user)
        assert_unsatisfied resource
      end

      test "when the org's business has restricted PATs for all orgs" do
        @business.reset_personal_access_tokens_restriction(actor: @user)
        @business.reload # avoid memoization
        assert_predicate @business, :personal_access_tokens_delegated_policy?

        @business_owned_org.permit_personal_access_tokens(actor: @user)
        @business_owned_org.reload # avoid memoization

        create_pat_for_user_on_restricted_org(on: @business_owned_org)

        @business.restrict_personal_access_tokens(actor: @user)
        refute_predicate @business, :personal_access_tokens_delegated_policy?

        resource = TestPersonalAccessTokensResource.new(target: @business_owned_org, actor: @user)
        assert_unsatisfied resource
      end
    end
  end

  context "#personal_access_tokens_satisfied" do
    context "is not satisfied" do
      test "when target is a business and the actor is a member" do
        create_pat_for_user_on_restricted_org(user: @user, on: @org)
        resource = TestPersonalAccessTokensResource.new(target: @business, actor: @user)
        assert_unsatisfied resource
      end

      test "when target is an org and the actor is a member" do
        create_pat_for_user_on_restricted_org(user: @user, on: @org)
        resource = TestPersonalAccessTokensResource.new(target: @org, actor: @user)
        assert_unsatisfied resource
      end

      test "when the user is an org billing manager" do
        manager = create(:user)
        @org.billing.add_manager(manager, actor: @user)

        create_pat_for_user(user: manager, on: manager)

        resource = TestPersonalAccessTokensResource.new(target: @org, actor: manager)
        assert_unsatisfied resource
      end

      test "when the user is a repo outside collaborator for an org" do
        collaborator = create(:user)
        repository   = create(:repository, :minimal, owner: @org)

        repository.add_member(collaborator)
        refute @org.direct_or_team_member?(collaborator)

        create_pat_for_user(user: collaborator, on: collaborator)

        resource = TestPersonalAccessTokensResource.new(target: @org, actor: collaborator)
        assert_unsatisfied resource
      end

      test "when the user is a repo outside collaborator for an org and the resource is an org" do
        collaborator = create(:user)
        repository   = create(:repository, :minimal, owner: @org)

        repository.add_member(collaborator)
        refute @org.direct_or_team_member?(collaborator)

        create_pat_for_user(user: collaborator, on: collaborator)

        resource = TestPersonalAccessTokensResource.new(target: @org, actor: collaborator)
        assert_unsatisfied resource
      end
    end

    context "is satisfied" do
      test "when target is a business and the actor is not a member" do
        not_a_biz_member = create(:user)

        create_pat_for_user(user: not_a_biz_member, on: not_a_biz_member)

        resource = TestPersonalAccessTokensResource.new(target: @business, actor: not_a_biz_member)
        assert_satisfied resource
      end

      test "when target is an org and the actor is not a member" do
        not_a_member = create(:user)

        create_pat_for_user(user: not_a_member, on: not_a_member)

        resource = TestPersonalAccessTokensResource.new(target: @org, actor: not_a_member)
        assert_satisfied resource
      end
    end
  end

  context "#multiple_personal_access_tokens_applicable" do
    test "returns nothing for anonymous requests" do
      skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

      callback = MockCallback.new
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_personal_access_tokens_applicable([@org], @target_provider)
    end

    test "returns nothing when the actor isn't a User" do
      skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

      bot = create(:integration).bot

      callback = MockCallback.new(actor_for_conditional_access: bot)
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_personal_access_tokens_applicable([@org], @target_provider)
    end

    test "returns nothing when the actor isn't using a PAT" do
      skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

      refute_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_personal_access_tokens_applicable([@org], target_provider: @target_provider)
    end

    test "returns resources of type Organization or Business" do
      skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

      user_repository = create(:repository, :minimal, owner: @user)
      org_repository = create(:repository, :minimal, owner: @org)

      create_pat_for_user_on_restricted_org(on: @org)
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
      skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = TestPersonalAccessTokensEnforcer.new(callback)

      assert_raises(ArgumentError) do
        policy.multiple_personal_access_tokens_satisfied([@user], @target_provider)
      end
    end

    test "returns satisfied orgs where the user is a member and are not directly restricted" do
      skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

      org_allowing_pat = create(:organization, admin: @user)
      org_allowing_pat.permit_personal_access_tokens(actor: @user)
      assert_predicate org_allowing_pat, :personal_access_tokens_allowed?

      assert_predicate @org, :personal_access_tokens_restricted?

      create_pat_for_user_on_restricted_org(on: @org)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal({ @org => { private: :unsatisfied }, org_allowing_pat => { private: :satisfied } }, policy.multiple_personal_access_tokens_satisfied(
        [@org, org_allowing_pat],
        @target_provider
      ))
    end

    test "returns satisfied businesses where the user is a member and PATs are not restricted" do
      skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

      @business.permit_personal_access_tokens(actor: @user)

      create_pat_for_user(on: @business_owned_org)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal({ @business => { private: :satisfied } }, policy.multiple_personal_access_tokens_satisfied([@business], @target_provider))
    end

    test "skips businesses where the user is a member but PATs are restricted" do
      skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

      create_pat_for_user_on_restricted_business_org(on: @business_owned_org)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal({ @business => { private: :unsatisfied } }, policy.multiple_personal_access_tokens_satisfied([@business], @target_provider))
    end

    test "return unsatisfied org where the owning business has restricted access" do
      skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

      create_pat_for_user_on_restricted_business_org(on: @business_owned_org)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal({ @business_owned_org => { private: :unsatisfied } }, policy.multiple_personal_access_tokens_satisfied([@business_owned_org], @target_provider))
    end

    test "returns orgs that allow PATs and belong to business without restriction" do
      skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

      @business.reset_personal_access_tokens_restriction(actor: @user)
      assert_predicate @business, :personal_access_tokens_allowed?

      @business_owned_org.permit_personal_access_tokens(actor: @user)

      create_pat_for_user(on: @business_owned_org)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal({ @business_owned_org => { private: :satisfied } }, policy.multiple_personal_access_tokens_satisfied(
        [@business_owned_org],
        @target_provider
      ))
    end

    test "returns unsatisfied orgs that allow PATs but belong to opted out business" do
      skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

      @business.reset_personal_access_tokens_restriction(actor: @user)
      @business_owned_org.permit_personal_access_tokens(actor: @user)
      @business.restrict_personal_access_tokens(actor: @user)

      create_pat_for_user_on_restricted_business_org(on: @business_owned_org)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal({ @business_owned_org => { private: :unsatisfied } }, policy.multiple_personal_access_tokens_satisfied([@business_owned_org], @target_provider))
    end

    test "return unsatisfied businesses that restrict access" do
      skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

      create_pat_for_user_on_restricted_business_org(on: @business_owned_org)
      assert_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal({ @business => { private: :unsatisfied } }, policy.multiple_personal_access_tokens_satisfied([@business], @target_provider))
    end
  end
end
