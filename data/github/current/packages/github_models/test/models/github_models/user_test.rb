# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::UserTest < GitHub::TestCase
  include CopilotPublicUserCacheable

  fixtures do
    @user = create(:user)
    @repo = create(:public_repository, owner: @user)

    disable_feature_flag(:project_neutron_higher_rate_limits)
    disable_feature_flag(:project_neutron_staff_account)
    disable_feature_flag(:project_neutron_rag)
  end

  setup do
    @prompt_code = <<~PROMPT
      const prompt = `You are a friendly expert`;

      const response = await client.path("/chat/completions").post({
          body: {
              messages: [{ role: "user", content: prompt }],
              model: model
          }
      });
    PROMPT

    @ref = @repo.heads.find_or_build("master")
    @ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
      files.add("foo.js", @prompt_code)
    end
    @blob = @repo.blob(@ref.sha, "foo.js")
  end

  context "#playground_url" do
    if GitHub.models_enabled?
      test "returns the models_gateway_url when the FF is enabled" do
        enable_feature_flag(:github_models_gateway)
        assert_match(GitHub.models_gateway_url, GitHubModels::User.new(user: @user).playground_url)
      end

      test "returns the azure_ai_playground_url when the FF is disabled" do
        disable_feature_flag(:github_models_gateway)
        assert_match(GitHub.azure_ai_playground_url, GitHubModels::User.new(user: @user).playground_url)
      end
    end
  end

  context "#can_use_o3_models?" do
    test "returns false when user has Copilot Free and feature is disabled" do
      disable_feature_flag(:project_neutron_o1_models)
      refute_predicate GitHubModels::User.new(user: @user), :can_use_o3_models?
    end

    test "returns true when user has Copilot Free and feature is enabled" do
      enable_feature_flag(:project_neutron_o1_models, @user)
      assert_predicate GitHubModels::User.new(user: @user), :can_use_o3_models?
    end

    test "returns false for anonymous user" do
      refute_predicate GitHubModels::User.new(user: nil), :can_use_o3_models?
    end

    test "returns true when user has a Copilot seat and o3 models access" do
      org = create(:copilot_for_business_enabled_organization, admin: @user)
      user = create(:copilot_seat, organization: org).assigned_user
      org.business.enable_models_access(@user)
      Copilot::Business.new(org.business).o3_enabled!

      assert_predicate GitHubModels::User.new(user: user), :can_use_o3_models?
    end

    test "returns false when user has a Copilot seat but o3 access is disabled" do
      disable_feature_flag(:project_neutron_o1_models)
      org = create(:copilot_for_business_enabled_organization, admin: @user)
      user = create(:copilot_seat, organization: org).assigned_user
      org.business.enable_models_access(@user)
      Copilot::Business.new(org.business).o3_disabled!

      refute_predicate GitHubModels::User.new(user: user), :can_use_o3_models?
    end
  end

  context "#can_use_o1_models?" do
    test "returns false when user is not present" do
      refute_predicate GitHubModels::User.new(user: nil), :can_use_o1_models?
    end

    test "returns true if user is in project_neutron_o1_models feature flag" do
      enable_feature_flag(:project_neutron_o1_models, @user)
      assert_predicate GitHubModels::User.new(user: @user), :can_use_o1_models?
    end

    test "returns false if user is not in project_neutron_o1_models feature flag and is a Copilot free tier user" do
      disable_feature_flag(:project_neutron_o1_models)
      user = create(:copilot_limited_user).user
      assert_predicate Copilot::Public::User.new(user), :has_copilot_individual_free_access?

      refute_predicate GitHubModels::User.new(user: user), :can_use_o1_models?
    end

    test "returns true if user has copilot access and has o1 enabled" do
      org = create(:copilot_for_business_enabled_organization, admin: @user)
      user = create(:copilot_seat, organization: org).assigned_user
      org.business.enable_models_access(@user)
      Copilot::Business.new(org.business).o1_enabled!

      assert_predicate GitHubModels::User.new(user: user), :can_use_o1_models?
    end

    test "returns false when user has a Copilot seat but o1 access is disabled" do
      disable_feature_flag(:project_neutron_o1_models)
      org = create(:copilot_for_business_enabled_organization, admin: @user)
      user = create(:copilot_seat, organization: org).assigned_user
      org.business.enable_models_access(@user)
      Copilot::Business.new(org.business).o1_disabled!

      refute_predicate GitHubModels::User.new(user: user), :can_use_o1_models?
    end
  end

  context "#models_access_allowed_for_blob?" do
    unless GitHub.models_enabled?
      test "returns false when models is not available in the environment" do
        res = GitHubModels::User.new(user: @user)
          .models_access_allowed_for_blob?(blob: @blob, blob_url: "blob-url/prompt", repository: @repo)
        refute res
      end
    end

    if GitHub.models_enabled?
      test "returns true for small blobs with prompt content in the name and no restrictions" do
        enable_feature_flag(:github_models_prompt_link)
        disable_feature_flag(:project_neutron_emergency_restrict_access)
        res = GitHubModels::User.new(user: @user)
          .models_access_allowed_for_blob?(blob: @blob, blob_url: "blob-url/prompt", repository: @repo)
        assert res
      end

      test "returns false when project_neutron_emergency_restrict_access is enabled" do
        enable_feature_flag(:project_neutron_emergency_restrict_access)
        res = GitHubModels::User.new(user: @user)
          .models_access_allowed_for_blob?(blob: @blob, blob_url: "blob-url/prompt", repository: @repo)
        refute res
      end

      test "returns false when the user can't access models" do
        spammy_user = create(:spammy_user)
        res = GitHubModels::User.new(user: spammy_user)
          .models_access_allowed_for_blob?(blob: @blob, blob_url: "blob-url/prompt", repository: @repo)
        refute res
      end

      test "returns false when the repo is owned by an org" do
        org_owned_repo = create(:repository, owner: create(:organization))

        res = GitHubModels::User.new(user: @user)
          .models_access_allowed_for_blob?(blob: @blob, blob_url: "blob-url/prompt", repository: org_owned_repo)
        refute res
      end

      test "returns false when the feature flag is disabled" do
        disable_feature_flag(:github_models_prompt_link)

        res = GitHubModels::User.new(user: @user)
          .models_access_allowed_for_blob?(blob: @blob, blob_url: "blob-url/prompt", repository: @repo)
        refute res
      end
    end
  end

  context "#is_staff?" do
    test "returns false when user is not present" do
      refute_predicate GitHubModels::User.new(user: nil), :is_staff?
    end

    test "returns true when user is an employee" do
      employee = create(:staff_admin_user)
      User.any_instance.stubs(:employee?).returns(true) # needed for EMU mode

      assert_predicate GitHubModels::User.new(user: employee), :is_staff?
    end

    test "returns true if user belongs to Microsoft business" do
      msft = create(:business, slug: "microsoft")
      # in EMU or MT test mode, the previous `create` may noop, so we need to update to ensure the slug is set
      msft.update!(slug: "microsoft")
      msft_user = msft.members.first

      assert_predicate GitHubModels::User.new(user: msft_user), :is_staff?
    end

    test "returns true if user is on the feature flag" do
      enable_feature_flag(:project_neutron_staff_account, @user)
      assert_predicate GitHubModels::User.new(user: @user), :is_staff?
    end

    test "returns is_staff false for others" do
      business = create(:business)
      other_user = business.members.first

      refute_predicate GitHubModels::User.new(user: other_user), :is_staff?
    end
  end

  context "#access_flights" do
    test "returns an empty array if user is a bot" do
      bot_user = create(:bot)
      assert_empty GitHubModels::User.new(user: bot_user).access_flights
    end

    test "returns an empty array if user is an organization" do
      org = create(:organization)
      assert_empty GitHubModels::User.new(user: org).access_flights
    end

    test "returns an empty array of user doesn't have access to o1 and o3 models and rag ff is off" do
      models_user = GitHubModels::User.new(user: @user)
      models_user.stubs(:can_use_o1_models?).returns(false)
      models_user.stubs(:can_use_o3_models?).returns(false)

      assert_empty models_user.access_flights
    end

    test "returns o1 models if user has access" do
      models_user = GitHubModels::User.new(user: @user)
      models_user.stubs(:can_use_o1_models?).returns(true)

      assert_includes models_user.access_flights, "o1-models"
    end

    test "returns o3 models if user has access" do
      models_user = GitHubModels::User.new(user: @user)
      models_user.stubs(:can_use_o3_models?).returns(true)

      assert_includes models_user.access_flights, "o3-models"
    end

    test "returns rag if feature flag enabled for user" do
      enable_feature_flag(:project_neutron_rag, @user)

      assert_includes GitHubModels::User.new(user: @user).access_flights, "rag"
    end
  end

  context "#usage_tier" do
    test "returns FREE tier as a free or Copilot Individual user" do
      user = create(:copilot_free_user).user

      assert_equal GitHubModels::User::USAGE_TIERS[:FREE], GitHubModels::User.new(user: user).usage_tier
    end

    test "returns BUSINESS tier as a Copilot Business user" do
      user = create(:copilot_seat).assigned_user

      assert_equal GitHubModels::User::USAGE_TIERS[:BUSINESS], GitHubModels::User.new(user: user).usage_tier
    end

    test "returns ENTERPRISE tier as a Copilot Enterprise user" do
      seat = create(:copilot_seat)
      Copilot::Business.new(seat.owner.business).copilot_plan_enterprise!
      Copilot::Organization.new(seat.owner).copilot_plan_enterprise!
      user = seat.assigned_user

      assert_equal GitHubModels::User::USAGE_TIERS[:ENTERPRISE], GitHubModels::User.new(user: user).usage_tier
    end

    test "returns STAFF tier for users on the feature flag" do
      enable_feature_flag(:project_neutron_higher_rate_limits, @user)

      assert_equal GitHubModels::User::USAGE_TIERS[:STAFF], GitHubModels::User.new(user: @user).usage_tier
    end
  end
end
