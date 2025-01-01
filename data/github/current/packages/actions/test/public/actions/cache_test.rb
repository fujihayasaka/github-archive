# typed: strict
# frozen_string_literal: true

require "test_helper"

class Actions::CacheTest < GitHub::TestCase
  fixtures do
    @repo = T.let(create(:repository), T.nilable(Repository))
  end

  test "enterprise always false", enterprise_only: true do
    disable_feature_flag(:actions_opt_out_of_cache_service_v2)
    enable_feature_flag(:actions_uses_cache_service_v2)

    refute Actions::Cache.use_v2?(@repo)
  end

  context "#use_v2?", skip_enterprise: true do
    test "false if all flags disabled" do
      disable_feature_flag(:actions_opt_out_of_cache_service_v2)
      disable_feature_flag(:actions_uses_cache_service_v2)

      refute Actions::Cache.use_v2?(@repo)
    end

    test "false if repository is opted out" do
      enable_feature_flag(:actions_opt_out_of_cache_service_v2, @repo)
      enable_feature_flag(:actions_uses_cache_service_v2)

      refute Actions::Cache.use_v2?(@repo)
    end

    test "false if owner is opted out" do
      enable_feature_flag(:actions_opt_out_of_cache_service_v2, @repo&.owner)
      enable_feature_flag(:actions_uses_cache_service_v2)

      refute Actions::Cache.use_v2?(@repo)
    end

    test "nil owner" do
      disable_feature_flag(:actions_opt_out_of_cache_service_v2)
      enable_feature_flag(:actions_uses_cache_service_v2)
      @repo&.owner = nil

      assert Actions::Cache.use_v2?(@repo)
    end

    test "true if enabled and not opted out" do
      disable_feature_flag(:actions_opt_out_of_cache_service_v2)
      enable_feature_flag(:actions_uses_cache_service_v2)

      assert Actions::Cache.use_v2?(@repo)
    end
  end
end
