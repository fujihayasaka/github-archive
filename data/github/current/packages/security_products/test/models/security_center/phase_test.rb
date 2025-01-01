# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class PhaseTest < GitHub::TestCase
    setup do
      disable_feature_flag(:my_feature_private_beta)
      disable_feature_flag(:my_feature)
    end

    context ".phase_for" do
      context "feature is not in beta", skip_enterprise: true do
        test "returns :alpha when feature is not enabled" do
          assert_equal :alpha, Phase.for_feature(:my_feature)
        end

        test "returns :alpha when feature is only enabled for specific actors" do
          enable_feature_flag(:my_feature, create(:user))
          assert_equal :alpha, Phase.for_feature(:my_feature)
        end

        test "returns :alpha when feature is only enabled for specific groups" do
          enable_feature_group(:my_feature, :preview_features)
          assert_equal :alpha, Phase.for_feature(:my_feature)
        end

        test "returns :ga when feature is enabled for a percentage of actors" do
          GitHub.flipper[:my_feature].enable_percentage_of_actors(0.01)
          assert_equal :ga, Phase.for_feature(:my_feature)
        end

        test "returns :ga when feature is partially dark shipped" do
          GitHub.flipper[:my_feature].enable_percentage_of_time(0.01)
          assert_equal :ga, Phase.for_feature(:my_feature)
        end

        test "returns :ga when feature is enabled for all actors" do
          GitHub.flipper[:my_feature].enable_percentage_of_actors(100)
          assert_equal :ga, Phase.for_feature(:my_feature)
        end

        test "returns :ga when feature is fully dark shipped" do
          GitHub.flipper[:my_feature].enable_percentage_of_time(100)
          assert_equal :ga, Phase.for_feature(:my_feature)
        end

        test "returns :ga when feature is fully enabled" do
          enable_feature_flag(:my_feature)
          assert_equal :ga, Phase.for_feature(:my_feature)
        end
      end

      context "feature is in beta", skip_enterprise: true do
        test "returns :private_beta when feature is not enabled" do
          enable_feature_flag(:my_feature_private_beta)
          assert_equal :private_beta, Phase.for_feature(:my_feature)
        end

        test "returns :private_beta when feature is only enabled for specific actors" do
          enable_feature_flag(:my_feature_private_beta)
          enable_feature_flag(:my_feature, create(:user))
          assert_equal :private_beta, Phase.for_feature(:my_feature)
        end

        test "returns :private_beta when feature is only enabled for specific groups" do
          enable_feature_flag(:my_feature_private_beta)
          enable_feature_group(:my_feature, :preview_features)
          assert_equal :private_beta, Phase.for_feature(:my_feature)
        end

        test "returns :beta when feature is enabled for a percentage of actors" do
          enable_feature_flag(:my_feature_private_beta)
          GitHub.flipper[:my_feature].enable_percentage_of_actors(0.01)
          assert_equal :beta, Phase.for_feature(:my_feature)
        end

        test "returns :beta when feature is partially dark shipped" do
          enable_feature_flag(:my_feature_private_beta)
          GitHub.flipper[:my_feature].enable_percentage_of_time(0.01)
          assert_equal :beta, Phase.for_feature(:my_feature)
        end

        test "returns :beta when feature is enabled for all actors" do
          enable_feature_flag(:my_feature_private_beta)
          GitHub.flipper[:my_feature].enable_percentage_of_actors(100)
          assert_equal :beta, Phase.for_feature(:my_feature)
        end

        test "returns :beta when feature is fully dark shipped" do
          enable_feature_flag(:my_feature_private_beta)
          GitHub.flipper[:my_feature].enable_percentage_of_time(100)
          assert_equal :beta, Phase.for_feature(:my_feature)
        end

        test "returns :beta when feature is fully enabled" do
          enable_feature_flag(:my_feature_private_beta)
          enable_feature_flag(:my_feature)
          assert_equal :beta, Phase.for_feature(:my_feature)
        end
      end

      context "enterprise", enterprise_only: true do
        test "returns :beta for any feature check in GHES" do
          assert_equal :beta, Phase.for_feature(:my_feature)
        end
      end
    end
  end
end
