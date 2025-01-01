# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectsClassicSunsetTest < GitHub::TestCase
  fixtures do
    @user = create(:verified_user)
  end

  setup do
    disable_feature_flag(ProjectsClassicSunset::SUNSET_OVERRIDE_FLAG)
    disable_feature_flag(ProjectsClassicSunset::SUNSET_REST_API_FLAG)
    disable_feature_flag(ProjectsClassicSunset::SUNSET_GRAPHQL_API_FLAG)
  end

  context "#rest_api_enabled?", skip_enterprise: true do
    test "returns true if entity is nil" do
      assert ProjectsClassicSunset.rest_api_enabled?(nil)
    end

    test "returns false if rest api is sunset" do
      enable_feature_flag(ProjectsClassicSunset::SUNSET_REST_API_FLAG)
      refute ProjectsClassicSunset.rest_api_enabled?(@user)
    end

    test "returns true if rest api is sunset and override flag is enabled" do
      enable_feature_flag(ProjectsClassicSunset::SUNSET_REST_API_FLAG)
      enable_feature_flag(ProjectsClassicSunset::SUNSET_OVERRIDE_FLAG)
      assert ProjectsClassicSunset.rest_api_enabled?(@user)
    end

    test "returns false if rest api is sunset for user" do
      enable_feature_flag(ProjectsClassicSunset::SUNSET_REST_API_FLAG, @user)
      refute ProjectsClassicSunset.rest_api_enabled?(@user)
    end

    test "returns true if rest api is sunset and override flag is enabled for user" do
      disable_feature_flag(ProjectsClassicSunset::SUNSET_REST_API_FLAG, @user)
      enable_feature_flag(ProjectsClassicSunset::SUNSET_OVERRIDE_FLAG)
      assert ProjectsClassicSunset.rest_api_enabled?(@user)
    end

    test "returns true if rest api is not sunset" do
      assert ProjectsClassicSunset.rest_api_enabled?(@user)
    end
  end

  context "#graphql_api_enabled?", skip_enterprise: true do
    test "returns true if entity is nil" do
      assert ProjectsClassicSunset.graphql_api_enabled?(nil)
    end

    test "returns false if graphql api is sunset" do
      enable_feature_flag(ProjectsClassicSunset::SUNSET_GRAPHQL_API_FLAG)
      refute ProjectsClassicSunset.graphql_api_enabled?(@user)
    end

    test "returns true if graphql api is sunset and override flag is enabled" do
      enable_feature_flag(ProjectsClassicSunset::SUNSET_GRAPHQL_API_FLAG)
      enable_feature_flag(ProjectsClassicSunset::SUNSET_OVERRIDE_FLAG)
      assert ProjectsClassicSunset.graphql_api_enabled?(@user)
    end

    test "returns false if graphql api is sunset for user" do
      enable_feature_flag(ProjectsClassicSunset::SUNSET_GRAPHQL_API_FLAG, @user)
      refute ProjectsClassicSunset.graphql_api_enabled?(@user)
    end

    test "returns true if graphql api is sunset and override flag is enabled for user" do
      disable_feature_flag(ProjectsClassicSunset::SUNSET_GRAPHQL_API_FLAG, @user)
      enable_feature_flag(ProjectsClassicSunset::SUNSET_OVERRIDE_FLAG)
      assert ProjectsClassicSunset.graphql_api_enabled?(@user)
    end

    test "returns true if graphql api is not sunset" do
      assert ProjectsClassicSunset.graphql_api_enabled?(@user)
    end
  end

  context "enterpise", enterprise_only: true do
    test "#rest_api_enabled?" do
      refute ProjectsClassicSunset.rest_api_enabled?(nil)
      refute ProjectsClassicSunset.rest_api_enabled?(@user)
    end

    test "#graphql_api_enabled?" do
      refute ProjectsClassicSunset.graphql_api_enabled?(nil)
      refute ProjectsClassicSunset.graphql_api_enabled?(@user)
    end
  end
end
