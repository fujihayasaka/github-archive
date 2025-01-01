# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class TenantValidationHelperTest < GitHub::TestCase
    fixtures do
      @org = create(:organization, skip_enterprise_managed_organization: true)
      @business_plus_org = create(:organization, plan: "business_plus")

      @biz = create(:business)
      @biz_owned_org = create(:organization, business: @biz)

      @repo = create(:repository, owner: @org)

      @ghes_org = create(:organization) if GitHub.single_business_environment?
    end

    setup do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(true)
      Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::FeatureEnablement).returns(true)
      Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::CodeScanningAlert).returns(true)
      Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::SecretScanningAlert).returns(true)
      Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::DependabotAlerts).returns(true)
    end

    context ".is_owner_in_scope?" do
      context "owner is an organization" do
        context "in dotcom", skip_enterprise: true do
          test "returns true if owner has advanced security purchased" do
            Organization.any_instance.expects(:advanced_security_purchased?).returns(true)
            assert(TenantValidationHelper.is_owner_in_scope?(@org))
          end

          test "returns true if owner has business plus plan" do
            Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
            assert(TenantValidationHelper.is_owner_in_scope?(@business_plus_org))
          end

          test "returns false if owner does not have GHAS and does not have business plus plan" do
            Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
            refute(TenantValidationHelper.is_owner_in_scope?(@org))
          end

          test "returns true if owner is owned by a paying business in dotcom" do
            Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
            assert(TenantValidationHelper.is_owner_in_scope?(@biz_owned_org))
          end

          test "returns false if owner's business is downgraded to free plan in dotcom" do
            Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
            @biz.downgrade_to_free_plan
            refute(TenantValidationHelper.is_owner_in_scope?(@biz_owned_org.reload))
          end
        end

        context "in GHES", enterprise_only: true do
          test "returns true on GHES" do
            assert(TenantValidationHelper.is_owner_in_scope?(@ghes_org))
          end
        end
      end

      context "owner is a user" do
        context "in dotcom", skip_enterprise: true do
          if TestEnv.test_with_all_emus?
            context "owner is an EMU" do
              test "returns true if GHAS is purchased" do
                Business.any_instance.expects(:advanced_security_purchased?).returns(true)
                assert(TenantValidationHelper.is_owner_in_scope?(@biz_owned_org.admins.first))
              end

              test "returns false if GHAS is not purchased" do
                Business.any_instance.expects(:advanced_security_purchased?).returns(false)
                refute(TenantValidationHelper.is_owner_in_scope?(@biz_owned_org.admins.first))
              end
            end
          end

          context "owner is not an EMU", skip_with_all_emus: true do
            test "returns false" do
              refute(TenantValidationHelper.is_owner_in_scope?(@biz_owned_org.admins.first))
            end
          end
        end

        context "in GHES", enterprise_only: true do
          test "returns true if EMUs are enabled for security center" do
            AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.expects(:feature_available?).returns(true)
            assert(TenantValidationHelper.is_owner_in_scope?(@biz_owned_org.admins.first))
          end

          test "returns false if EMUs are disabled for security center" do
            AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.expects(:feature_available?).returns(false)
            refute(TenantValidationHelper.is_owner_in_scope?(@biz_owned_org.admins.first))
          end
        end
      end
    end

    context ".should_handle_repository_lifecycle_events?" do
      test "returns false if the owner does not exist" do
        @business_plus_org.destroy
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(false)
        refute(TenantValidationHelper.should_handle_repository_lifecycle_events?(@business_plus_org.id))
      end

      test "returns false if the owner is not in scope" do
        TenantValidationHelper.expects(:is_owner_in_scope?).returns(false)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(false)
        refute(TenantValidationHelper.should_handle_repository_lifecycle_events?(@business_plus_org.id))
      end

      test "returns false if the owner is not onboarded" do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
        Initialization.any_instance.expects(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(false)
        refute(TenantValidationHelper.should_handle_repository_lifecycle_events?(@business_plus_org.id))
      end

      test "returns true if the owner is an onboarded organization" do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(true)
        assert(TenantValidationHelper.should_handle_repository_lifecycle_events?(@business_plus_org.id))
      end

      test "returns true if the owner is an onboarded user" do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(true)
        assert(TenantValidationHelper.should_handle_repository_lifecycle_events?(@business_plus_org.admins.first.id))
      end
    end

    context ".should_handle_feature_enablement_events?" do
      test "returns false if GHEC organization does not have GHAS and does not have business plus plan", skip_enterprise: true do
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
        refute(TenantValidationHelper.should_handle_feature_enablement_events?(@org.id))
      end

      test "returns true if organization has advanced security purchased" do
        assert(TenantValidationHelper.should_handle_feature_enablement_events?(@org.id))
      end

      test "returns true if organization has business plus plan" do
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
        assert(TenantValidationHelper.should_handle_feature_enablement_events?(@business_plus_org.id))
      end

      test "returns false if organization does not exist" do
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
        @business_plus_org.destroy
        refute(TenantValidationHelper.should_handle_feature_enablement_events?(@business_plus_org.id))
      end

      test "returns false if a feature enablement initialization does not exist" do
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::FeatureEnablement).returns(false)
        refute(TenantValidationHelper.should_handle_feature_enablement_events?(@org.id))
      end

      test "returns true if a feature enablement initialization exists" do
        assert(TenantValidationHelper.should_handle_feature_enablement_events?(@org.id))
      end
    end

    context ".should_handle_code_scanning_alert_events?" do
      test "returns false if input is nil" do
        refute(TenantValidationHelper.should_handle_code_scanning_alert_events?(nil))
      end

      test "returns false if input is not an organization" do
        user = create(:user)
        refute(TenantValidationHelper.should_handle_code_scanning_alert_events?(user))
      end

      test "returns false if GHEC organization does not have GHAS and does not have business plus plan", skip_enterprise: true do
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
        refute(TenantValidationHelper.should_handle_code_scanning_alert_events?(@org))
      end

      test "returns true if organization has advanced security purchased" do
        assert(TenantValidationHelper.should_handle_code_scanning_alert_events?(@org))
      end

      test "returns true if organization has business plus plan" do
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
        assert(TenantValidationHelper.should_handle_code_scanning_alert_events?(@business_plus_org))
      end

      test "returns false if a code scanning alert initialization does not exist" do
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::CodeScanningAlert).returns(false)
        refute(TenantValidationHelper.should_handle_code_scanning_alert_events?(@org))
      end

      test "returns true if a feature enablement initialization exists" do
        assert(TenantValidationHelper.should_handle_code_scanning_alert_events?(@org))
      end
    end

    context ".should_handle_secret_scanning_alert_events?" do
      test "returns false if input is nil" do
        refute(TenantValidationHelper.should_handle_secret_scanning_alert_events?(nil))
      end

      test "returns false if input is not an organization, EMU, or Enterprise User", skip_with_all_emus: true, skip_enterprise: true do
        user = create(:user)
        refute(TenantValidationHelper.should_handle_secret_scanning_alert_events?(user))
      end

      if TestEnv.test_with_all_emus? || GitHub.enterprise?
        test "returns true if input is an EMU and GHAS is purchased" do
          Business.any_instance.expects(:advanced_security_purchased?).returns(true)
          user = create(:user)
          assert(TenantValidationHelper.should_handle_secret_scanning_alert_events?(user))
        end

        test "returns false if input is an EMU and GHAS is not purchased" do
          Business.any_instance.expects(:advanced_security_purchased?).returns(false)
          user = create(:user)
          refute(TenantValidationHelper.should_handle_secret_scanning_alert_events?(user))
        end
      end

      test "returns false if GHEC organization does not have GHAS and does not have business plus plan", skip_enterprise: true do
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
        refute(TenantValidationHelper.should_handle_secret_scanning_alert_events?(@org))
      end

      test "returns true if organization has advanced security purchased" do
        assert(TenantValidationHelper.should_handle_secret_scanning_alert_events?(@org))
      end

      test "returns true if organization has business plus plan" do
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
        assert(TenantValidationHelper.should_handle_secret_scanning_alert_events?(@business_plus_org))
      end

      test "returns false if a secret scanning alert initialization does not exist" do
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::SecretScanningAlert).returns(false)
        refute(TenantValidationHelper.should_handle_secret_scanning_alert_events?(@org))
      end

      test "returns true if a feature enablement initialization exists" do
        assert(TenantValidationHelper.should_handle_secret_scanning_alert_events?(@org))
      end
    end

    context ".should_handle_dependabot_alert_events?" do
      test "return true if repo is eligible to have Dependabot alerts ingested" do
        assert TenantValidationHelper.should_handle_dependabot_alert_events?(@repo)
      end

      test "return false if repo owner is not an organization" do
        repo = create(:repository, owner: @org.admin)
        refute TenantValidationHelper.should_handle_dependabot_alert_events?(repo)
      end

      test "return false if repo owner is not in scope" do
        TenantValidationHelper.expects(:is_owner_in_scope?).with(@org).returns(false)
        refute TenantValidationHelper.should_handle_dependabot_alert_events?(@repo)
      end

      test "return false if repo owner is not onboarded for Dependabot alerts" do
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::DependabotAlerts).returns(false)
        refute TenantValidationHelper.should_handle_dependabot_alert_events?(@repo)
      end
    end
  end
end
