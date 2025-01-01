# typed: true
# frozen_string_literal: true

require "test_helper"

module EnterpriseCloudOnboard
  class GhasTrialTest < GitHub::TestCase
    fixtures do
      make_trusted_oauth_apps_owner
      create(:launch_integration)

      @owner = create(:user)
      @organization = create(:organization, admin: @owner, plan: GitHub::Plan.business)
      @repo = OrganizationOnboard::DemoRepository.new(organization: @organization).setup(@owner)&.repository

      @business = create(:business, owners: [@owner])
      @org_from_business = create(:organization, admin: @owner, plan: GitHub::Plan.business)
      @business.add_organization(@org_from_business)
      @repo_from_business = OrganizationOnboard::DemoRepository.new(organization: @org_from_business).setup(@owner)&.repository

      create(:billing_product_uuid, :advanced_security)
    end


    context "with organizations" do
      context "#enable" do
        test "enables GHAS in the org and in the demo repo" do
          refute @repo.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
          EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @organization).enable

          @repo.reload
          @organization.reload

          assert @organization.advanced_security_purchased_for_entity?
          assert @organization.advanced_security_trial_enabled_for_entity?
          refute @organization.advanced_security_enabled_on_new_repos?
          assert @repo.advanced_security_enabled?
          assert SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
        end

        test "enables GHAS in the org with custom number of days" do
          refute @repo.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
          EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @organization).enable(5)

          @repo.reload
          @organization.reload

          assert @organization.advanced_security_purchased_for_entity?
          assert @organization.advanced_security_trial_enabled_for_entity?
          refute @organization.advanced_security_enabled_on_new_repos?
          assert @repo.advanced_security_enabled?
          assert SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
          assert_equal @organization.advanced_security_trial_number_of_days, 5
        end

        test "enables GHAS in the org with max number of days" do
          refute @repo.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
          EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @organization).enable(999)

          @repo.reload
          @organization.reload

          assert @organization.advanced_security_purchased_for_entity?
          assert @organization.advanced_security_trial_enabled_for_entity?
          refute @organization.advanced_security_enabled_on_new_repos?
          assert @repo.advanced_security_enabled?
          assert SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
          assert_equal @organization.advanced_security_trial_number_of_days, 90
        end

        test "does not enable GHAS if the user is not the owner" do
          user = create(:user)
          @organization.add_member(user)
          refute @repo.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
          EnterpriseCloudOnboard::GhasTrial.new(actor: user, billable_entity: @organization).enable

          @repo.reload
          @organization.reload

          refute @organization.advanced_security_purchased_for_entity?
          refute @organization.advanced_security_trial_enabled_for_entity?
          refute @repo.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
        end
      end

      context "#disable" do
        test "disables GHAS in the org" do
          refute @repo.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
          ghas_trial = EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @organization)
          freeze_time do
            ghas_trial.enable
            @organization.reload
            @repo.reload
            assert_equal Date.current + 30.days, @organization.get_advanced_security_trial_expires_at

            assert @organization.advanced_security_purchased_for_entity?
            assert @organization.advanced_security_trial_enabled_for_entity?
            assert @repo.advanced_security_enabled?
            assert SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
            assert Configuration::Entry.where(
              name: Configurable::AdvancedSecurityTrialConfig::ADVANCED_SECURITY_TRIAL_DAYS_KEY,
            ).exists?

            ghas_trial.disable
            @repo.reload
            @organization.reload

            assert_equal Date.current + 30.days, @organization.get_advanced_security_trial_expires_at
            refute @organization.advanced_security_purchased_for_entity?
            refute @organization.advanced_security_trial_enabled_for_entity?
            refute @repo.advanced_security_enabled?
            refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
            refute Configuration::Entry.where(
              name: Configurable::AdvancedSecurityTrialConfig::ADVANCED_SECURITY_TRIAL_DAYS_KEY,
            ).exists?
          end
        end

        test "disables GHAS trial even if GHAS is already disabled" do
          refute @repo.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
          ghas_trial = EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @organization)
          ghas_trial.enable

          @repo.reload
          @organization.reload

          @organization.mark_advanced_security_as_not_purchased_for_entity(actor: @owner)
          @organization.reload

          refute @organization.advanced_security_purchased_for_entity?
          assert @organization.advanced_security_trial_enabled_for_entity?
          refute @repo.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?

          ghas_trial.disable
          @repo.reload
          @organization.reload

          refute @organization.advanced_security_purchased_for_entity?
          refute @organization.advanced_security_trial_enabled_for_entity?
          refute @repo.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
        end

        test "disables GHAS even if GHAS trial is already disabled" do
          refute @repo.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
          ghas_trial = EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @organization)
          ghas_trial.enable

          @repo.reload
          @organization.reload

          @organization.disable_advanced_security_trial_for_entity(actor: @owner)
          @organization.reload

          assert @organization.advanced_security_purchased_for_entity?
          refute @organization.advanced_security_trial_enabled_for_entity?
          assert @repo.advanced_security_enabled?
          assert SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?

          ghas_trial.disable
          @repo.reload
          @organization.reload

          refute @organization.advanced_security_purchased_for_entity?
          refute @organization.advanced_security_trial_enabled_for_entity?
          refute @repo.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
        end
      end
    end

    context "with enterprises" do
      context "#enable" do
        test "enables GHAS in the org and in the demo repo" do
          refute @repo_from_business.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo_from_business).enabled?
          EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @business).enable

          @repo_from_business.reload
          @business.reload
          @org_from_business.reload
          assert @business.advanced_security_purchased_for_entity?
          assert @business.advanced_security_trial_enabled_for_entity?
          refute @org_from_business.advanced_security_enabled_on_new_repos?

          assert @repo_from_business.advanced_security_enabled?
          assert SecretScanning::Features::Repo::TokenScanning.new(@repo_from_business).enabled?
        end

        test "does not enable GHAS if the user is not the owner" do
          user = create(:user)
          @org_from_business.add_member(user)
          refute @repo_from_business.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo_from_business).enabled?
          EnterpriseCloudOnboard::GhasTrial.new(actor: user, billable_entity: @business).enable

          @repo_from_business.reload
          @organization.reload

          refute @business.advanced_security_purchased_for_entity?
          refute @business.advanced_security_trial_enabled_for_entity?
          refute @repo_from_business.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo_from_business).enabled?
        end
      end

      context "#disable" do
        test "disable GHAS in the enterprise" do
          refute @repo_from_business.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo_from_business).enabled?
          ghas_trial = EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @business)
          freeze_time do
            ghas_trial.enable
            @repo_from_business.reload
            @business.reload
            assert_equal Date.current + 30.days, @business.get_advanced_security_trial_expires_at

            assert @business.advanced_security_purchased_for_entity?
            assert @business.advanced_security_trial_enabled_for_entity?
            assert @repo_from_business.advanced_security_enabled?
            assert SecretScanning::Features::Repo::TokenScanning.new(@repo_from_business).enabled?

            ghas_trial.disable
            @repo_from_business.reload
            @business.reload

            assert_equal Date.current + 30.days, @business.get_advanced_security_trial_expires_at
            refute @business.advanced_security_purchased_for_entity?
            refute @business.advanced_security_trial_enabled_for_entity?
            refute @business.advanced_security_trial_enabled_for_entity?

            refute @repo_from_business.advanced_security_enabled?
            refute SecretScanning::Features::Repo::TokenScanning.new(@repo_from_business).enabled?
          end
        end
      end

      context "#prolong" do
        test "prolongs GHAS trial number of days" do
          EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @business).enable(10)
          @business.reload
          assert @business.advanced_security_trial_enabled_for_entity?
          assert_equal @business.advanced_security_trial_number_of_days, 10

          EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @business).prolong(5)
          @business.reload
          @org_from_business.reload

          assert @business.advanced_security_trial_enabled_for_entity?
          refute @org_from_business.advanced_security_enabled_on_new_repos?
          assert_equal @business.advanced_security_trial_number_of_days, 15
        end

        test "does not prolong GHAS trial number of days if trial is not enabled" do
          refute @organization.advanced_security_trial_enabled_for_entity?

          EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @business).prolong(10)
          @business.reload
          refute @business.advanced_security_trial_enabled_for_entity?
        end
      end
    end

    context "with an organization belonging to an enterprise" do
      context "#enable" do
        test "enables GHAS in the org and in the demo repo" do
          refute @repo_from_business.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo_from_business).enabled?
          EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @org_from_business).enable

          @repo_from_business.reload
          @org_from_business.reload
          @business.reload
          refute @org_from_business.advanced_security_purchased_for_entity?
          refute @org_from_business.advanced_security_trial_enabled_for_entity?

          assert @business.advanced_security_purchased_for_entity?
          assert @business.advanced_security_trial_enabled_for_entity?
          refute @org_from_business.advanced_security_enabled_on_new_repos?

          assert @repo_from_business.advanced_security_enabled?
          assert SecretScanning::Features::Repo::TokenScanning.new(@repo_from_business).enabled?
        end

        test "does not enable GHAS if the user is not the owner" do
          user = create(:user)
          @org_from_business.add_member(user)
          refute @repo_from_business.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo_from_business).enabled?
          EnterpriseCloudOnboard::GhasTrial.new(actor: user, billable_entity: @org_from_business).enable

          @repo_from_business.reload
          @org_from_business.reload

          refute @org_from_business.advanced_security_purchased_for_entity?
          refute @org_from_business.advanced_security_trial_enabled_for_entity?
          refute @repo_from_business.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo_from_business).enabled?
        end
      end

      context "#disable" do
        test "disable GHAS in the enterprise" do
          refute @repo_from_business.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo_from_business).enabled?
          ghas_trial = EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @business)
          ghas_trial.enable
          @repo_from_business.reload
          @business.reload

          assert @business.advanced_security_purchased_for_entity?
          assert @business.advanced_security_trial_enabled_for_entity?
          assert @repo_from_business.advanced_security_enabled?
          assert SecretScanning::Features::Repo::TokenScanning.new(@repo_from_business).enabled?

          ghas_trial.disable
          @repo_from_business.reload
          @business.reload

          refute @org_from_business.advanced_security_purchased_for_entity?
          refute @org_from_business.advanced_security_trial_enabled_for_entity?
          refute @repo_from_business.advanced_security_enabled?
          refute SecretScanning::Features::Repo::TokenScanning.new(@repo_from_business).enabled?
        end
      end

      context "#expires_at" do
        test "returns expiration date" do
          freeze_time do
            ghas_trial = EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @business)
            ghas_trial.enable
            assert_equal Date.current + 30.days, ghas_trial.expires_at
          end
        end

        test "returns nil if trial is disabled" do
          freeze_time do
            ghas_trial = EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @business)
            assert_nil ghas_trial.expires_at
          end
        end
      end

      context "#expired?" do
        test "returns true when expires_at is less than today" do
          EnterpriseCloudOnboard::GhasTrial.any_instance.stubs(:expires_at).returns(Date.current - 1.day)
          ghas_trial = EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @business)

          assert ghas_trial.expired?
        end


        test "returns false when expires_at is greater than today" do
          EnterpriseCloudOnboard::GhasTrial.any_instance.stubs(:expires_at).returns(Date.current + 1.day)
          ghas_trial = EnterpriseCloudOnboard::GhasTrial.new(actor: @owner, billable_entity: @business)

          refute ghas_trial.expired?
        end
      end
    end
  end
end unless GitHub.enterprise?
