# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::BusinessTrials::EnterpriseTrialSyncJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  fixtures do
    @organization = create(:enterprise_linked_organization)
    @trial = create(:copilot_business_trial, :organization, trialable: @organization)
    @user = create(:user)
  end

  setup do
    GitHub.flipper[:copilot_business_trial_job].enable
  end

  context "perform" do
    context "validation" do
      test "does nothing if flag is disabled" do
        GitHub.flipper[:copilot_business_trial_job].disable

        logs = capture_logs do
          Copilot::BusinessTrials::EnterpriseTrialSyncJob.perform_now(1, :CANCELLED, @user, "123", {})
        end

        assert_match "Skipping Copilot::BusinessTrials::EnterpriseTrialSyncJob", logs
      end

      test "does nothing with invalid action" do
        assert_raises(ArgumentError) do
          Copilot::BusinessTrials::EnterpriseTrialSyncJob.perform_now(1, :INVALID, @user, "123", {})
        end
      end

      test "does nothing with invalid business" do
        Copilot::ErrorReporter.expects(:report!).with do |error, _context|
          error.is_a?(Copilot::Errors::CopilotError)
        end

        Copilot::BusinessTrials::EnterpriseTrialSyncJob.perform_now(0, :CANCELLED, @user, "123", {})
      end

      test "does nothing with no trial organizations" do
        business = create(:business)

        logs = capture_logs do
          Copilot::BusinessTrials::EnterpriseTrialSyncJob.perform_now(business.id, :CANCELLED, business.admins.first, "123", {})
        end

        assert_match "No trial organizations found", logs
      end
    end

    context "cancel" do
      test "cancels multiple trials" do
        other_organization = create(:enterprise_linked_organization, business: @organization.business)
        other_trial = create(:copilot_business_trial, :organization, trialable: other_organization)

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::BusinessTrials::EnterpriseTrialSyncJob.perform_now(
              @organization.business.id,
              :CANCELLED,
              @organization.business.admins.first,
              "123",
              {},
            )
          end
        end

        assert_match "Canceling CFB trials", logs
        assert_match "gh.copilot.business_trial.id=\"#{@trial.id}", logs
        assert_match "gh.copilot.business_trial.id=\"#{other_trial.id}", logs

        @trial.reload
        assert_equal "canceled", @trial.state

        other_trial.reload
        assert_equal "canceled", other_trial.state
      end

      test "expires trials" do
        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::BusinessTrials::EnterpriseTrialSyncJob.perform_now(
              @organization.business.id,
              :EXPIRED,
              @organization.business.admins.first,
              "123",
              {},
            )
          end
        end

        assert_match "Canceling CFB trials", logs
        assert_match "gh.copilot.business_trial.id=\"#{@trial.id}", logs

        @trial.reload
        assert_equal "canceled", @trial.state
      end

      test "upgrades trials" do
        Copilot::Organization.any_instance.expects(:copilot_billable?).returns(true)
        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::BusinessTrials::EnterpriseTrialSyncJob.perform_now(
              @organization.business.id,
              :UPGRADED,
              @organization.business.admins.first,
              "123",
              {},
            )
          end
        end

        assert_match "Upgrading business trial", logs
        assert_match "gh.copilot.business_trial.id=\"#{@trial.id}", logs

        @trial.reload
        assert_equal "upgraded", @trial.state
      end

      test "logs if trial is not upgradable" do
        Copilot::BusinessTrial.any_instance.stubs(:upgradable?).returns(false)

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::BusinessTrials::EnterpriseTrialSyncJob.perform_now(
              @organization.business.id,
              :UPGRADED,
              @organization.business.admins.first,
              "123",
              {},
            )
          end
        end

        assert_match "Copilot business trial is not upgradable", logs

        refute @trial.reload.upgraded?
      end
    end

    context "syncs" do
      test "sends an exception if no trial" do
        business = create(:business)
        refute business.trial?
        refute business.trial_expires_at

        organization = create(:enterprise_linked_organization, business: business)
        create(:copilot_business_trial, :organization, trialable: organization)

        Copilot::ErrorReporter.expects(:report!).once
        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::BusinessTrials::EnterpriseTrialSyncJob.perform_now(
              business.id,
              :EXTENDED,
              business.admins.first,
              "123",
              {},
            )
          end
        end

        assert_match "No trial expiration date for business", logs
      end

      test "syncs a single trial" do
        business = create(:business)
        business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        assert business.trial?

        organization = create(:enterprise_linked_organization, business: business)
        trial = create(:copilot_business_trial, :organization, trialable: organization)

        business.extend_trial(organization.admins.first)
        business.reload

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::BusinessTrials::EnterpriseTrialSyncJob.perform_now(
              business.id,
              :EXTENDED,
              business.admins.first,
              "123",
              {},
            )
          end
        end

        assert_match "Syncing CFB trials", logs
        assert_match "gh.copilot.business_trial.id=\"#{trial.id}", logs

        trial.reload
        assert_equal business.trial_expires_at.to_date, trial.ends_at.to_date
      end

      test "syncs multiple trials" do
        business = create(:business)
        business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        assert business.trial?

        organization = create(:enterprise_linked_organization, business: business)
        trial = create(:copilot_business_trial, :organization, trialable: organization)

        another_organization = create(:enterprise_linked_organization, business: business)
        another_trial = create(:copilot_business_trial, :organization, trialable: another_organization)

        business.extend_trial(organization.admins.first)
        business.reload

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::BusinessTrials::EnterpriseTrialSyncJob.perform_now(
              business.id,
              :EXTENDED,
              business.admins.first,
              "123",
              {},
            )
          end
        end

        assert_match "Syncing CFB trials", logs
        assert_match "gh.copilot.business_trial.id=\"#{trial.id}", logs
        assert_match "gh.copilot.business_trial.id=\"#{another_trial.id}", logs

        trial.reload
        assert_equal business.trial_expires_at.to_date, trial.ends_at.to_date

        another_trial.reload
        assert_equal business.trial_expires_at.to_date, another_trial.ends_at.to_date
      end
    end
  end
end if GitHub.copilot_enabled?
