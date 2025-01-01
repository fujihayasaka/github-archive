# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationBetaFeaturesDependencyTest < GitHub::TestCase
  fixtures do
    @admin = create :user
    @org = create(:free_organization, seats: 0, admin: @admin)
    @team_org = create(:business_org, admin: @admin)
    @trial_org = create(:free_organization, admin: @admin)
    Billing::EnterpriseCloudTrial.new(@trial_org).create
    @beta_features = %w[my_test_feature my_test_feature2]
  end

  setup do
    if TestEnv.test_all_features?
      GitHub.flipper[:my_test_feature].disable
      GitHub.flipper[:my_test_feature2].disable
    end
  end

  def stub_beta_features(&block)
    Organization::BetaFeaturesDependency.stub_const(:BETA_FEATURES, @beta_features) do
      ::Flipper::Config.stub_const(:BIG_FEATURES, @beta_features) do
        yield
      end
    end
  end

  def enable_beta_features_for(org)
    @beta_features.each do |feature|
      GitHub.flipper[feature].enable_actor(org)
    end
  end

  def disable_beta_features_for(org)
    @beta_features.each do |feature|
      GitHub.flipper[feature].disable_actor(org)
    end
  end

  context "#set_beta_features_for_plan" do
    if GitHub.organization_beta_enrollment_enabled?
      test "trial plan with flag: enables features" do
        disable_beta_features_for(@trial_org)

        stub_beta_features do
          @trial_org.set_beta_features_for_plan

          assert GitHub.flipper[:my_test_feature].enabled?(@trial_org)
          assert GitHub.flipper[:my_test_feature2].enabled?(@trial_org)
        end
      end

      test "trial plan: leaves flags alone" do
        enable_beta_features_for(@trial_org)

        stub_beta_features do
          @trial_org.set_beta_features_for_plan

          assert GitHub.flipper[:my_test_feature].enabled?(@trial_org)
          assert GitHub.flipper[:my_test_feature2].enabled?(@trial_org)
        end
      end

      test "business plan: enables features" do
        disable_beta_features_for(@team_org)

        stub_beta_features do
          @team_org.set_beta_features_for_plan

          assert GitHub.flipper[:my_test_feature].enabled?(@team_org)
          assert GitHub.flipper[:my_test_feature2].enabled?(@team_org)
        end
      end

      test "doesn't change features for free plan" do
        enable_beta_features_for(@org)
        stub_beta_features do
          @org.set_beta_features_for_plan

          assert GitHub.flipper[:my_test_feature].enabled?(@org)
          assert GitHub.flipper[:my_test_feature2].enabled?(@org)
        end
      end

      test "requires features to be defined as Big Features" do
        Organization::BetaFeaturesDependency.stub_const(:BETA_FEATURES, @beta_features) do
          ::Flipper::Config.stub_const(:BIG_FEATURES, ["my_test_feature"]) do
            # in this case, my_test_feature2 is a "beta feature"
            # but is not a "big feature", so we should expect an error.

            assert_raises Organization::BetaFeaturesDependency::MissingBigFeatureError do
              @team_org.set_beta_features_for_plan
              refute GitHub.flipper[:my_test_feature].enabled?(@team_org)
            end
          end
        end
      end

      test "forces cache to be updated even if updated_at from org does not change" do
        # This is required because on organization creation we store the cache
        # when calling Billing::EnterpriseCloudTrial.new(self).active? after
        # calling #set_beta_features_for_plan and some times at the same exactly
        # time we create the Billing::PlanTrial, making the organization
        # updated_at with the same value and the cache does not get expired when
        # calling Billing::EnterpriseCloudTrial.new(self).active? again.
        #
        # See: https://github.com/github/github/pull/201479
        with_cache_enabled do
          freeze_time do
            @org.touch
            refute Billing::EnterpriseCloudTrial.new(@org).active?

            Billing::EnterpriseCloudTrial.new(@org).create

            @org.set_beta_features_for_plan
            assert Billing::EnterpriseCloudTrial.new(@org).active?
          end
        end
      end

    else
      test "does nothing" do
        refute @org.set_beta_features_for_plan
      end
    end
  end
end
