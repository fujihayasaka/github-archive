# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features
  class SecretScanningFeatureFlagHelperTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    context "feature_flag_enabled?", skip_enterprise: true do
      test "enabled on user" do
        user = create(:user)
        GitHub.flipper[:test_repo_feature].enable(user)
        assert feature_flag_enabled?(user, :test_repo_feature)
      end

      test "enabled on repo" do
        repo = create(:repository)
        GitHub.flipper[:test_repo_feature].enable(repo)
        assert feature_flag_enabled?(repo, :test_repo_feature)
      end

      test "enabled for org and its repositories" do
        org = create(:organization)
        GitHub.flipper[:test_org_feature].enable(org)

        repo1 = create(:repository, owner: org)
        repo2 = create(:repository, owner: org)
        assert feature_flag_enabled?(repo1, :test_org_feature)
        assert feature_flag_enabled?(repo2, :test_org_feature)
      end

      test "enabled for user and its repositories" do
        user = create(:user)
        GitHub.flipper[:test_user_feature].enable(user)

        repo1 = create(:repository, owner: user)
        repo2 = create(:repository, owner: user)
        assert feature_flag_enabled?(repo1, :test_user_feature)
        assert feature_flag_enabled?(repo2, :test_user_feature)
      end

      test "enabled on business and its orgs and repositories" do
        business = create(:business)
        GitHub.flipper[:test_biz_feature].enable(business)
        org1 = create(:business_plus_org, business: business)
        org2 = create(:business_plus_org, business: business)
        repo1 = create(:repository, owner: org1)
        repo2 = create(:repository, owner: org1)
        repo3 = create(:repository, owner: org2)
        repo4 = create(:repository, owner: org2)


        assert feature_flag_enabled?(org1, :test_biz_feature)
        assert feature_flag_enabled?(org2, :test_biz_feature)
        assert feature_flag_enabled?(repo1, :test_biz_feature)
        assert feature_flag_enabled?(repo2, :test_biz_feature)
        assert feature_flag_enabled?(repo3, :test_biz_feature)
        assert feature_flag_enabled?(repo4, :test_biz_feature)
      end
    end
  end
end
