# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/policy_test_helper"

class CapLegacyPersonalAccessTokensPolicyTest < GitHub::TestCase
  include ConditionalAccess::PolicyTestHelpers

  class TestLegacyPatEnforcer < ConditionalAccess::Api::Public::Enforcer
    def initialize(actor)
      super(MockCallback.new(actor: actor))
    end

    def conditional_access_policies
      [:legacy_personal_access_tokens]
    end
    alias :registered_policies :conditional_access_policies

    def location
      :test
    end
  end

  class TestLegacyPatFilter < ConditionalAccess::Api::Public::Filter
    def initialize(actor)
      super(MockCallback.new(actor: actor))
    end

    def conditional_access_policies
      [:legacy_personal_access_tokens]
    end
    alias :registered_policies :conditional_access_policies

    def location
      :test
    end
  end

  class MockCallback
    attr_reader :actor
    alias :actor_for_conditional_access :actor
    alias :actor_for_conditional_access_authzd :actor
    alias :current_user :actor

    sig { params(actor: T.untyped).void }
    def initialize(actor: nil)
      @actor = actor
    end

    sig { returns(T::Boolean) }
    def logged_in?
      actor.present?
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
    @user_filter = TestLegacyPatFilter.new(@user)
    @user_enforcer = TestLegacyPatEnforcer.new(@user)
  end

  def policy_name
    :legacy_personal_access_tokens
  end

  context "#legacy_personal_access_tokens_applicable" do
    test "is not applicable for anonymous requests" do
      enforcer = TestLegacyPatEnforcer.new(nil)
      assert_inapplicable(enforcer, @org)
    end

    test "is not applicable when the actor isn't a User" do
      bot = create(:integration).bot

      enforcer = TestLegacyPatEnforcer.new(bot)
      assert_inapplicable(enforcer, @org)
    end

    test "is not applicable when the actor isn't using a legacy PAT" do
      @org.restrict_legacy_personal_access_tokens(actor: @user)

      @user.oauth_access = create(:oauth_access, user: @user)
      refute_predicate @user, :using_personal_access_token?

      assert_inapplicable(@user_enforcer, @org)
    end

    test "is not applicable when the resource has no target for conditional access" do
      @user.oauth_access = @user_pat
      assert_predicate @user, :using_personal_access_token?

      assert_inapplicable(@user_enforcer, :no_target_for_conditional_access)
    end

    test "is not applicable when the resources's TFCA is not an Org or Business" do
      repository = create(:repository, :minimal, owner: @user)
      assert_equal @user, repository.target_for_conditional_access

      @user.oauth_access = @user_pat
      assert_predicate @user, :using_personal_access_token?

      assert_inapplicable(@user_enforcer, repository)
    end

    test "is not applicable when the resource's TFCA is an org but the org hasn't restricted legacy PAT access" do
      org_repo = create(:repository, :minimal, owner: @org)
      assert_equal @org, org_repo.target_for_conditional_access

      @user.oauth_access = @user_pat
      assert_predicate @user, :using_personal_access_token?

      assert_inapplicable(@user_enforcer, org_repo)
    end

    test "is not applicable when the org's business has allowed legacy PATs for all orgs" do
      @business_owned_org.restrict_legacy_personal_access_tokens(actor: @user)
      @business.permit_legacy_personal_access_tokens(actor: @user)

      @user.oauth_access = @user_pat
      assert_predicate @user, :using_personal_access_token?

      assert_inapplicable(@user_enforcer, @business_owned_org)
    end

    context "is applicable" do
      test "when the resource's TFCA is an org that has restricted legacy PATs" do
        @org.restrict_legacy_personal_access_tokens(actor: @user)
        org_repo = create(:repository, :minimal, owner: @org)

        @user.oauth_access = @user_pat
        assert_predicate @user, :using_personal_access_token?

        assert_unsatisfied(@user_enforcer, org_repo)
      end

      test "when the business has restricted legacy PATs" do
        @business.restrict_legacy_personal_access_tokens(actor: @user)

        @user.oauth_access = @user_pat
        assert_predicate @user, :using_personal_access_token?

        assert_unsatisfied(@user_enforcer, @business)
      end

      test "when the org's business has restricted legacy PATs for all orgs" do
        @business_owned_org.permit_legacy_personal_access_tokens(actor: @user)
        @business.restrict_legacy_personal_access_tokens(actor: @user)

        @user.oauth_access = @user_pat
        assert_predicate @user, :using_personal_access_token?

        assert_unsatisfied(@user_enforcer, @business_owned_org)
      end
    end
  end

  context "#legacy_personal_access_tokens_satisfied" do
    context "is satisfied" do
      test "when the user is not a business member" do
        # This behavior allows non-members to access public resources via PAT
        # However, biz members still cannot access public biz-owned resources
        # This should be revisited with the CAP visibility work.
        rando = create(:user)

        @business.restrict_legacy_personal_access_tokens(actor: @user)
        rando.oauth_access = create(:oauth_access, :personal_token, user: rando)
        assert_predicate rando, :using_personal_access_token?

        enforcer = TestLegacyPatEnforcer.new(rando)
        assert_satisfied(enforcer, @business)
      end

      test "when the user is an outside collaborator on an org repo but not a business member" do
        @business.restrict_legacy_personal_access_tokens(actor: @user)

        collaborator = create(:user)
        collaborator.oauth_access = create(:oauth_access, :personal_token, user: collaborator)
        assert_predicate collaborator, :using_personal_access_token?

        # if this line is run before '@business.restrict_legacy_personal_access_tokens(actor: @user)', the test fails (actual = inapplicable)
        # if this line is run after, the test passes (actual = unsatisfied)
        # why??? For some reason the config entry is not present when CAP runs if this line runs first
        repository   = create(:repository, :minimal, owner: @business_owned_org)

        repository.add_member(collaborator)
        refute @business_owned_org.direct_or_team_member?(collaborator)


        enforcer = TestLegacyPatEnforcer.new(collaborator)
        assert_unsatisfied(enforcer, repository)
        assert_unsatisfied(enforcer, @business_owned_org)
        assert_satisfied(enforcer, @business)
      end

      test "when the user is unaffiliated with the organization" do
        # This behavior allows non-members to access public resources via PAT
        # However, org members still cannot access public org-owned resources
        # This should be revisited with the CAP visibility work.
        rando = create(:user)

        @org.restrict_legacy_personal_access_tokens(actor: @user)
        rando.oauth_access = create(:oauth_access, :personal_token, user: rando)
        assert_predicate rando, :using_personal_access_token?

        enforcer = TestLegacyPatEnforcer.new(rando)
        assert_satisfied(enforcer, @org)
      end
    end

    context "is not satisfied" do
      test "when the user is a business member" do
        @business.restrict_legacy_personal_access_tokens(actor: @user)
        @user.oauth_access = @user_pat
        assert_predicate @user, :using_personal_access_token?

        assert_unsatisfied(@user_enforcer, @business)
      end

      test "when the user is an org member" do
        @org.restrict_legacy_personal_access_tokens(actor: @user)
        @user.oauth_access = @user_pat
        assert_predicate @user, :using_personal_access_token?

        assert_unsatisfied(@user_enforcer, @org)
      end

      test "when the user is an org billing manager" do
        manager = create(:user)
        @org.billing.add_manager(manager, actor: @user)

        @org.restrict_legacy_personal_access_tokens(actor: @user)
        manager.oauth_access = create(:oauth_access, :personal_token, user: manager)
        assert_predicate manager, :using_personal_access_token?

        enforcer = TestLegacyPatEnforcer.new(manager)
        assert_unsatisfied(enforcer, @org)
      end

      test "when the user is an repo outside collaborator for an org" do
        collaborator = create(:user)
        repository   = create(:repository, :minimal, owner: @org)

        repository.add_member(collaborator)
        refute @org.direct_or_team_member?(collaborator)

        @org.restrict_legacy_personal_access_tokens(actor: @user)
        collaborator.oauth_access = create(:oauth_access, :personal_token, user: collaborator)
        assert_predicate collaborator, :using_personal_access_token?

        enforcer = TestLegacyPatEnforcer.new(collaborator)
        assert_unsatisfied(enforcer, repository)
      end

      test "when the user is a repo outside collaborator for an org and the resource is an org" do
        collaborator = create(:user)
        repository   = create(:repository, :minimal, owner: @org)

        repository.add_member(collaborator)
        refute @org.direct_or_team_member?(collaborator)

        @org.restrict_legacy_personal_access_tokens(actor: @user)
        collaborator.oauth_access = create(:oauth_access, :personal_token, user: collaborator)
        assert_predicate collaborator, :using_personal_access_token?

        enforcer = TestLegacyPatEnforcer.new(collaborator)
        assert_unsatisfied(enforcer, @org)
      end
    end
  end

  context "#multiple_legacy_personal_access_tokens_applicable" do
    test "inapplicable for anonymous requests" do
      filter   = TestLegacyPatFilter.new(nil)
      assert_filter(filter, [@org], { @org => :inapplicable })
    end

    test "inapplicable when the actor isn't a User" do
      bot = create(:integration).bot
      filter = TestLegacyPatFilter.new(bot)
      assert_filter(filter, [@org], { @org => :inapplicable })
    end

    test "inapplicable when the actor isn't using a legacy PAT" do
      @org.restrict_legacy_personal_access_tokens(actor: @user)

      @user.oauth_access = create(:oauth_access, user: @user)
      refute_predicate @user, :using_personal_access_token?

      assert_filter(@user_filter, [@org], { @org => :inapplicable })
    end

    test "applicable for resources of type Organization or Business" do
      user_repository = create(:repository, :minimal, owner: @user)
      org_repository = create(:repository, :minimal, owner: @org)

      @user.oauth_access = @user_pat
      assert_predicate @user, :using_personal_access_token?

      assert_filter(@user_filter, [user_repository, org_repository, @business, @org], {
        user_repository => :inapplicable,
        org_repository => :satisfied,
        @business => :satisfied,
        @org => :satisfied,
      })
    end
  end

  context "#multiple_legacy_personal_access_tokens_satisfied" do
    test "satisfied for orgs where the user is a member and are not directly restricted" do
      @org.restrict_legacy_personal_access_tokens(actor: @user)
      other_org = create(:organization, admin: @user)

      @user.oauth_access = @user_pat
      assert_predicate @user, :using_personal_access_token?

      assert_filter(@user_filter, [@org, other_org], {
        @org => :unsatisfied,
        other_org => :satisfied,
      })
    end

    test "unsatisfied for orgs where the owning business has restricted access" do
      @business.restrict_legacy_personal_access_tokens(actor: @user)

      @user.oauth_access = @user_pat
      assert_predicate @user, :using_personal_access_token?

      assert_filter(@user_filter, [@business_owned_org], { @business_owned_org => :unsatisfied })
    end

    test "unsatisfied for businesses that restrict access" do
      @business.restrict_legacy_personal_access_tokens(actor: @user)

      @user.oauth_access = @user_pat
      assert_predicate @user, :using_personal_access_token?

      assert_filter(@user_filter, [@business], { @business => :unsatisfied })
    end
  end
end
