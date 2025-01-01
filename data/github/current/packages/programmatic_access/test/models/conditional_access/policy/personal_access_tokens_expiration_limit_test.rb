# typed: true
# frozen_string_literal: true

require "test_helper"

class CapPersonalAccessTokensExpirationLimitPolicyTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers

  class FakeEnforcer < ConditionalAccess::Api::Public::Enforcer # Use an existing enforcer to make Sorbet happy.
    DEFAULT_POLICIES = [
      :personal_access_tokens_expiration_limit
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

    @business = create :business, owners: [@user]
    @business_owned_org = create :business_plus_org, admin: @user
    @business.add_organization(@business_owned_org)

    GitHub.flipper[:cap_pats_policy_enforcement].enable(@user)
  end

  setup do
    @target_provider = ConditionalAccess::TargetProvider.new(location: :test, callback_name: "test")
  end

  def create_fg_pat_for_user(on: @org, user: @user)
    user.programmatic_access = make_user_programmatic_access_with_grant(
      requester: @user, target: on,
    )

    user.programmatic_access
  end

  def create_pat_classic_for_user(user: @user)
    user.oauth_access = create(:oauth_access, :personal_token, user: user, scopes: %w(repo))
    user.oauth_access
  end

  context "#personal_access_tokens_expiration_limit_applicable" do
    test "is not applicable for anonymous requests" do
      callback = MockCallback.new
      policy   = FakeEnforcer.new(callback)

      assert_predicate policy, :anonymous?
      assert_equal :no, policy.personal_access_tokens_expiration_limit_applicable(resource: @org, target_provider: @target_provider)
    end

    test "is not applicable when the actor isn't a User" do
      bot = create(:integration).bot

      callback = MockCallback.new(actor_for_conditional_access: bot)
      policy   = FakeEnforcer.new(callback)

      assert_equal :no, policy.personal_access_tokens_expiration_limit_applicable(resource: @org, target_provider: @target_provider)
    end

    test "is not applicable when the actor isn't using a PAT" do
      refute_predicate @user, :using_auth_via_user_programmatic_access?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_equal :no, policy.personal_access_tokens_expiration_limit_applicable(resource: @org, target_provider: @target_provider)
    end

    context "actor is using a fine-grained PAT" do
      test "is not applicable when the resource has no target for conditional access" do
        create_fg_pat_for_user(on: @org)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.personal_access_tokens_expiration_limit_applicable(resource: :no_target_for_conditional_access, target_provider: @target_provider)
      end

      test "is not applicable when org does not have a pat expiration limit" do
        create_fg_pat_for_user(on: @org)
        @org.disable_fine_grained_personal_access_token_expiration_limit(actor: @user)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.personal_access_tokens_expiration_limit_applicable(resource: @org, target_provider: @target_provider)
      end

      test "is not applicable when org has a pat expiration limit and the admin is exempt at the business" do
        create_fg_pat_for_user(on: @business_owned_org)
        @business_owned_org.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 7)
        @business.enable_fine_grained_personal_access_token_expiration_limit_exemption(actor: @user)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.personal_access_tokens_expiration_limit_applicable(resource: @business_owned_org.reload, target_provider: @target_provider)
      end

      test "is applicable when org has a pat expiration limit and the admin is not exempt on the business" do
        create_fg_pat_for_user(on: @business_owned_org)
        @business_owned_org.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 7)
        @business.disable_fine_grained_personal_access_token_expiration_limit_exemption(actor: @user)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.personal_access_tokens_expiration_limit_applicable(resource: @business_owned_org.reload, target_provider: @target_provider)
      end

      test "is applicable when business has a pat expiration limit and the org does not have" do
        create_fg_pat_for_user(on: @business_owned_org)
        @business_owned_org.disable_fine_grained_personal_access_token_expiration_limit(actor: @user)
        @business.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 7)
        @business.disable_fine_grained_personal_access_token_expiration_limit_exemption(actor: @user)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.personal_access_tokens_expiration_limit_applicable(resource: @business_owned_org.reload, target_provider: @target_provider)
      end

      test "is applicable when org has a pat expiration limit and the admin is not exempt on the business but enforcement FF is disabled" do
        create_fg_pat_for_user(on: @business_owned_org)
        @business_owned_org.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 7)
        @business.disable_fine_grained_personal_access_token_expiration_limit_exemption(actor: @user)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        GitHub.flipper[:cap_pats_policy_enforcement].disable(@user)

        assert_equal :no, policy.personal_access_tokens_expiration_limit_applicable(resource: @business_owned_org.reload, target_provider: @target_provider)
      end
    end

    context "actor is using a PAT (classic)" do
      test "is not applicable when the resource has no target for conditional access" do
        create_pat_classic_for_user

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.personal_access_tokens_expiration_limit_applicable(resource: :no_target_for_conditional_access, target_provider: @target_provider)
      end

      test "is not applicable when org does not have a pat expiration limit" do
        create_pat_classic_for_user
        @org.disable_personal_access_token_classic_expiration_limit(actor: @user)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.personal_access_tokens_expiration_limit_applicable(resource: @org, target_provider: @target_provider)
      end

      test "is not applicable when org has a pat expiration limit and the admin is exempt at the business" do
        create_pat_classic_for_user
        @business_owned_org.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)
        @business.enable_personal_access_token_classic_expiration_limit_exemption(actor: @user)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :no, policy.personal_access_tokens_expiration_limit_applicable(resource: @business_owned_org.reload, target_provider: @target_provider)
      end

      test "is applicable when org has a pat expiration limit and the admin is not exempt on the business" do
        create_pat_classic_for_user
        @business_owned_org.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)
        @business.disable_personal_access_token_classic_expiration_limit_exemption(actor: @user)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.personal_access_tokens_expiration_limit_applicable(resource: @business_owned_org.reload, target_provider: @target_provider)
      end

      test "is applicable when business has a pat expiration limit and the org does not have" do
        create_pat_classic_for_user
        @business_owned_org.disable_personal_access_token_classic_expiration_limit(actor: @user)
        @business.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)
        @business.disable_personal_access_token_classic_expiration_limit_exemption(actor: @user)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.personal_access_tokens_expiration_limit_applicable(resource: @business_owned_org.reload, target_provider: @target_provider)
      end

      test "is not applicable when org has a pat expiration limit and the admin is not exempt on the business and enforcement FF disabled" do
        create_pat_classic_for_user
        @business_owned_org.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)
        @business.disable_personal_access_token_classic_expiration_limit_exemption(actor: @user)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        GitHub.flipper[:cap_pats_policy_enforcement].disable(@user)

        assert_equal :no, policy.personal_access_tokens_expiration_limit_applicable(resource: @business_owned_org.reload, target_provider: @target_provider)
      end
    end
  end

  context "#personal_access_tokens_expiration_limit_satisfied" do
    context "is not satisfied" do
      context "actor is using a fine-grained PAT" do
        test "when the user is a repo outside collaborator for an org" do
          collaborator = create(:user)
          repository   = create(:repository, :minimal, owner: @org)

          repository.add_member(collaborator)
          refute @org.direct_or_team_member?(collaborator)

          pat = create_fg_pat_for_user(on: @org, user: collaborator)
          pat.expires_at = 30.days.from_now
          @org.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 7)

          callback = MockCallback.new(actor_for_conditional_access: collaborator)
          policy   = FakeEnforcer.new(callback)

          assert_equal :no, policy.personal_access_tokens_expiration_limit_satisfied(resource: repository, target_provider: @target_provider)
        end

        test "when the user is a repo outside collaborator for an org and the target is an org" do
          collaborator = create(:user)
          repository   = create(:repository, :minimal, owner: @org)

          repository.add_member(collaborator)
          refute @org.direct_or_team_member?(collaborator)

          pat = create_fg_pat_for_user(on: @org, user: collaborator)
          pat.expires_at = 30.days.from_now
          @org.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 7)

          callback = MockCallback.new(actor_for_conditional_access: collaborator)
          policy   = FakeEnforcer.new(callback)

          assert_equal :no, policy.personal_access_tokens_expiration_limit_satisfied(resource: @org, target_provider: @target_provider)
        end

        test "when PAT does not adhere the target expiration limit" do
          pat = create_fg_pat_for_user(on: @org)
          pat.expires_at = 30.days.from_now
          @org.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 7)

          callback = MockCallback.new(actor_for_conditional_access: @user)
          policy   = FakeEnforcer.new(callback)

          assert_equal :no, policy.personal_access_tokens_expiration_limit_satisfied(resource: @org.reload, target_provider: @target_provider)
        end
      end

      context "actor is using a PAT (classic)" do
        test "when the user is a repo outside collaborator for an org" do
          collaborator = create(:user)
          repository   = create(:repository, :minimal, owner: @org)

          repository.add_member(collaborator)
          refute @org.direct_or_team_member?(collaborator)

          pat = create_pat_classic_for_user(user: collaborator)
          pat.expires_at = 30.days.from_now
          @org.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)

          callback = MockCallback.new(actor_for_conditional_access: collaborator)
          policy   = FakeEnforcer.new(callback)

          assert_equal :no, policy.personal_access_tokens_expiration_limit_satisfied(resource: repository, target_provider: @target_provider)
        end

        test "when the user is a repo outside collaborator for an org and the target is an org" do
          collaborator = create(:user)
          repository   = create(:repository, :minimal, owner: @org)

          repository.add_member(collaborator)
          refute @org.direct_or_team_member?(collaborator)

          pat = create_pat_classic_for_user(user: collaborator)
          pat.expires_at = 30.days.from_now
          @org.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)

          callback = MockCallback.new(actor_for_conditional_access: collaborator)
          policy   = FakeEnforcer.new(callback)

          assert_equal :no, policy.personal_access_tokens_expiration_limit_satisfied(resource: @org, target_provider: @target_provider)
        end

        test "when PAT does not adhere the target expiration limit" do
          pat = create_pat_classic_for_user
          pat.expires_at = 30.days.from_now
          @org.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)

          callback = MockCallback.new(actor_for_conditional_access: @user)
          policy   = FakeEnforcer.new(callback)

          assert_equal :no, policy.personal_access_tokens_expiration_limit_satisfied(resource: @org.reload, target_provider: @target_provider)
        end

        test "when PAT has no expiration" do
          pat = create_pat_classic_for_user
          pat.expires_at = nil
          @org.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)

          callback = MockCallback.new(actor_for_conditional_access: @user)
          policy   = FakeEnforcer.new(callback)

          assert_equal :no, policy.personal_access_tokens_expiration_limit_satisfied(resource: @org.reload, target_provider: @target_provider)
        end

        if GitHub.enterprise?
          test "when PAT has no issue date and the target does not exempt missing issue date" do
            pat = create_pat_classic_for_user
            pat.last_issued_at = nil
            @business_owned_org.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)

            callback = MockCallback.new(actor_for_conditional_access: @user)
            policy   = FakeEnforcer.new(callback)

            assert_equal :no, policy.personal_access_tokens_expiration_limit_satisfied(resource: @business_owned_org.reload, target_provider: @target_provider)
          end

          test "when PAT has no issue date and the target exempts missing issue date", feature_enabled: :pat_issued_at_exemption do
            pat = create_pat_classic_for_user
            pat.last_issued_at = nil
            @business_owned_org.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)
            @business.enable_personal_access_token_classic_missing_issued_at_exemption(actor: @user)

            callback = MockCallback.new(actor_for_conditional_access: @user)
            policy   = FakeEnforcer.new(callback)

            assert_equal :yes, policy.personal_access_tokens_expiration_limit_satisfied(resource: @business_owned_org.reload, target_provider: @target_provider)
          end

          test "when PAT has no issue date and the target exempts missing issue date", feature_disabled: :pat_issued_at_exemption do
            pat = create_pat_classic_for_user
            pat.last_issued_at = nil
            @business_owned_org.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)
            @business.enable_personal_access_token_classic_missing_issued_at_exemption(actor: @user)

            callback = MockCallback.new(actor_for_conditional_access: @user)
            policy   = FakeEnforcer.new(callback)

            assert_equal :no, policy.personal_access_tokens_expiration_limit_satisfied(resource: @business_owned_org.reload, target_provider: @target_provider)
          end
        end
      end
    end

    context "is satisfied" do
      test "when target is a business and the actor is not a member" do
        not_a_biz_member = create(:user)

        callback = MockCallback.new(actor_for_conditional_access: not_a_biz_member)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.personal_access_tokens_expiration_limit_satisfied(resource: @business, target_provider: @target_provider)
      end

      test "when target is an org and the actor is not a member" do
        not_a_member = create(:user)

        callback = MockCallback.new(actor_for_conditional_access: not_a_member)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.personal_access_tokens_expiration_limit_satisfied(resource: @org, target_provider: @target_provider)
      end

      test "when fine-grained PAT does adhere the target expiration limit" do
        pat = create_fg_pat_for_user(on: @org)
        pat.expires_at = 7.days.from_now
        @org.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 7)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.personal_access_tokens_expiration_limit_satisfied(resource: @org.reload, target_provider: @target_provider)
      end

      test "when PAT (classic) does adhere the target expiration limit" do
        pat = create_pat_classic_for_user
        pat.expires_at = 7.days.from_now
        @org.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal :yes, policy.personal_access_tokens_expiration_limit_satisfied(resource: @org.reload, target_provider: @target_provider)
      end
    end
  end

  context "#multiple_personal_access_tokens_expiration_limit_applicable" do
    test "returns nothing for anonymous requests" do
      callback = MockCallback.new
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_personal_access_tokens_expiration_limit_applicable([@org], @target_provider)
    end

    test "returns nothing when the actor isn't a User" do
      bot = create(:integration).bot

      callback = MockCallback.new(actor_for_conditional_access: bot)
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_personal_access_tokens_expiration_limit_applicable([@org], @target_provider)
    end

    test "returns nothing when the actor isn't using a PAT" do
      refute_predicate @user, :using_auth_via_user_programmatic_access?
      refute_predicate @user, :using_personal_access_token?

      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_empty policy.multiple_personal_access_tokens_expiration_limit_applicable([@org], target_provider: @target_provider)
    end

    context "actor is using a fine-grained PAT" do
      test "returns resources of type Organization or Business" do
        user_repository = create(:repository, :minimal, owner: @user)
        org_repository = create(:repository, :minimal, owner: @org)

        create_fg_pat_for_user(on: @org)
        assert_predicate @user, :using_auth_via_user_programmatic_access?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        applicable = policy.multiple_personal_access_tokens_expiration_limit_applicable(
          [:no_target_for_conditional_access, user_repository, org_repository, @business, @org],
          @target_provider
        )

        assert_same_elements [@business, @org], applicable
      end

      test "returns nothing when they have limits but enforcement FF disabled" do
        user_repository = create(:repository, :minimal, owner: @user)
        org_repository = create(:repository, :minimal, owner: @org)

        create_fg_pat_for_user(on: @org)
        assert_predicate @user, :using_auth_via_user_programmatic_access?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        GitHub.flipper[:cap_pats_policy_enforcement].disable(@user)

        applicable = policy.multiple_personal_access_tokens_expiration_limit_applicable(
          [:no_target_for_conditional_access, user_repository, org_repository, @business, @org],
          @target_provider
        )

        assert_same_elements [], applicable
      end
    end

    context "actor is using a PAT (classic)" do
      test "returns resources of type Organization or Business" do
        user_repository = create(:repository, :minimal, owner: @user)
        org_repository = create(:repository, :minimal, owner: @org)

        create_pat_classic_for_user
        assert_predicate @user, :using_personal_access_token?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        applicable = policy.multiple_personal_access_tokens_expiration_limit_applicable(
          [:no_target_for_conditional_access, user_repository, org_repository, @business, @org],
          @target_provider
        )

        assert_same_elements [@business, @org], applicable
      end

      test "returns no resources when enforcement FF disabled" do
        user_repository = create(:repository, :minimal, owner: @user)
        org_repository = create(:repository, :minimal, owner: @org)

        create_pat_classic_for_user
        assert_predicate @user, :using_personal_access_token?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        GitHub.flipper[:cap_pats_policy_enforcement].disable(@user)

        applicable = policy.multiple_personal_access_tokens_expiration_limit_applicable(
          [:no_target_for_conditional_access, user_repository, org_repository, @business, @org],
          @target_provider
        )

        assert_same_elements [], applicable
      end
    end
  end

  context "#multiple_personal_access_tokens_expiration_limit_satisfied" do
    test "raises when one of the targets has an invalid type" do
      callback = MockCallback.new(actor_for_conditional_access: @user)
      policy   = FakeEnforcer.new(callback)

      assert_raises(ArgumentError) do
        policy.multiple_personal_access_tokens_expiration_limit_satisfied([@user], @target_provider)
      end
    end

    context "actor is using a fine-grained PAT" do
      test "returns satisfied businesses where the user is a member and there is no PAT expiration limit" do
        @business.disable_fine_grained_personal_access_token_expiration_limit(actor: @user)

        pat = create_fg_pat_for_user(on: @business_owned_org)
        pat.expires_at = 7.days.from_now
        assert_predicate @user, :using_auth_via_user_programmatic_access?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal({ @business => { private: :satisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business], @target_provider))
      end

      test "returns businesses where the user is a member and PATs adheres the expiration limit" do
        pat = create_fg_pat_for_user(on: @business_owned_org)
        pat.expires_at = 6.days.from_now
        assert_predicate @user, :using_auth_via_user_programmatic_access?
        @business.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 7)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal({ @business => { private: :satisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business], @target_provider))
      end

      test "skips businesses where the user is a member and PATs does not adhere the expiration limit" do
        pat = create_fg_pat_for_user(on: @business_owned_org)
        pat.expires_at = 30.days.from_now
        @business.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 7)

        assert_predicate @user, :using_auth_via_user_programmatic_access?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal({ @business => { private: :unsatisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business], @target_provider))
      end

      test "returns unsatisfied orgs where the owning business has limits stricter than the org" do
        pat = create_fg_pat_for_user(on: @business_owned_org)
        pat.expires_at = 25.days.from_now
        assert_predicate @user, :using_auth_via_user_programmatic_access?
        @business.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 7)
        @org.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 30)

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal({ @business_owned_org => { private: :unsatisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business_owned_org], @target_provider))
      end

      test "return unsatisfied orgs where the owning business has limits and the pat does not adhere it" do
        pat = create_fg_pat_for_user(on: @business_owned_org)
        pat.expires_at = 30.days.from_now
        @business.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 7)

        assert_predicate @user, :using_auth_via_user_programmatic_access?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal({ @business_owned_org => { private: :unsatisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business_owned_org], @target_provider))
      end

      test "returns satisfied orgs where the owning business has limits and the pat does not adhere it but actor is exempted" do
        @business.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 7)
        @business.enable_fine_grained_personal_access_token_expiration_limit_exemption(actor: @user)

        pat = create_fg_pat_for_user(on: @business_owned_org)
        pat.expires_at = 30.days.from_now
        assert_predicate @user, :using_auth_via_user_programmatic_access?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal({ @business_owned_org => { private: :satisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business_owned_org], @target_provider))
      end

      test "returns satisfied businesses where the user is an admin and business exempts admins" do
        @business.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 7)
        @business.enable_fine_grained_personal_access_token_expiration_limit_exemption(actor: @user)

        pat = create_fg_pat_for_user(on: @business_owned_org)
        pat.expires_at = 30.days.from_now
        assert_predicate @user, :using_auth_via_user_programmatic_access?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal({ @business => { private: :satisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business], @target_provider))
      end
    end

    context "actor is using a PAT (classic)" do
      test "returns businesses where the user is a member and there is no PAT expiration limit" do
        @business.disable_personal_access_token_classic_expiration_limit(actor: @user)

        pat = create_pat_classic_for_user
        pat.expires_at = 7.days.from_now
        assert_predicate @user, :using_personal_access_token?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal({ @business => { private: :satisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business], @target_provider))
      end

      test "returns satisfied businesses where the user is a member and PATs adheres the expiration limit" do
        @business.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)

        pat = create_pat_classic_for_user
        pat.expires_at = 6.days.from_now
        assert_predicate @user, :using_personal_access_token?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal({ @business => { private: :satisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business], @target_provider))
      end

      test "skips businesses where the user is a member and PATs does not adhere the expiration limit" do
        @business.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)

        pat = create_pat_classic_for_user
        pat.expires_at = 30.days.from_now
        assert_predicate @user, :using_personal_access_token?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal({ @business => { private: :unsatisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business], @target_provider))
      end

      test "unsatisfies businesses where the user is a member and the PAT has no expiration" do
        @business.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)

        pat = create_pat_classic_for_user
        assert_predicate @user, :using_personal_access_token?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_nil pat.expires_at

        assert_equal({ @business => { private: :unsatisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business], @target_provider))
      end

      test "does not return orgs where the owning business has limits stricter than the org" do
        @business.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)
        @org.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 30)

        pat = create_pat_classic_for_user
        pat.expires_at = 25.days.from_now
        assert_predicate @user, :using_personal_access_token?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal({ @business_owned_org => { private: :unsatisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business_owned_org], @target_provider))
      end

      test "returns unsatisfied orgs where the owning business has limits and the pat does not adhere it" do
        @business.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)

        pat = create_pat_classic_for_user
        pat.expires_at = 30.days.from_now
        assert_predicate @user, :using_personal_access_token?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_equal({ @business_owned_org => { private: :unsatisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business_owned_org], @target_provider))
      end

      test "returns unsatisfied orgs where the owning business has limits and the pat has no expiration" do
        @business.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)

        pat = create_pat_classic_for_user
        assert_predicate @user, :using_personal_access_token?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        assert_nil pat.expires_at

        assert_equal({ @business_owned_org => { private: :unsatisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business_owned_org], @target_provider))
      end

      test "returns satisfied orgs where the owning business has limits and the pat does not adhere it but actor is exempted" do
        @business.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)

        pat = create_pat_classic_for_user
        pat.expires_at = 30.days.from_now
        assert_predicate @user, :using_personal_access_token?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        @business.enable_personal_access_token_classic_expiration_limit_exemption(actor: @user)

        assert_equal({ @business_owned_org => { private: :satisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business_owned_org], @target_provider))
      end

      test "returns businesses where the user is an admin and business exempts admins" do
        @business.set_personal_access_token_classic_expiration_limit(actor: @user, expiration: 7)

        pat = create_pat_classic_for_user
        pat.expires_at = 30.days.from_now
        assert_predicate @user, :using_personal_access_token?

        callback = MockCallback.new(actor_for_conditional_access: @user)
        policy   = FakeEnforcer.new(callback)

        @business.enable_personal_access_token_classic_expiration_limit_exemption(actor: @user)

        assert_equal({ @business => { private: :satisfied } }, policy.multiple_personal_access_tokens_expiration_limit_satisfied([@business], @target_provider))
      end
    end
  end
end
