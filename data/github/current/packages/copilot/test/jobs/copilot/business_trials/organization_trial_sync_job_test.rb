# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::BusinessTrials::OrganizationTrialSyncJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  fixtures do
    @organization = create(:trial_business_plus_organization)
    @trial = create(:copilot_business_trial, :organization, trialable: @organization)
  end

  setup do
    GitHub.flipper[:copilot_business_trial_job].enable
  end

  context "performs" do
    context "validations" do
      test "does nothing if flag is disabled" do
        GitHub.flipper[:copilot_business_trial_job].disable
        logs = capture_logs do
          Copilot::BusinessTrials::OrganizationTrialSyncJob.perform_now(1, :EXTENDED, "123", {})
        end

        assert_match "Skipping Copilot::BusinessTrials::OrganizationTrialSyncJob", logs
      end

      test "does nothing with invalid action" do
        assert_raises(ArgumentError) do
          Copilot::BusinessTrials::OrganizationTrialSyncJob.perform_now(1, :INVALID, "123", {})
        end
      end

      test "does nothing with invalid organization" do
        Copilot::ErrorReporter.expects(:report!).with do |error, _context|
          error.is_a?(Copilot::Errors::CopilotError)
        end

        Copilot::BusinessTrials::OrganizationTrialSyncJob.perform_now(0, :EXTENDED, "123", {})
      end
    end

    context "cancel" do
      test "cancels trial" do
        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::BusinessTrials::OrganizationTrialSyncJob.perform_now(@organization.id, :EXPIRED, "123", {})
          end
        end

        assert_match "Canceling trial", logs
        assert_match "gh.copilot.business_trial.id=\"#{@trial.id}", logs

        @trial.reload
        assert_equal "canceled", @trial.state
      end
    end

    context "syncs" do
      test "sends an exception if no trial" do
        organization = create(:business_plus_organization)
        create(:copilot_business_trial, :organization, trialable: organization)

        Copilot::ErrorReporter.expects(:report!).once
        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::BusinessTrials::OrganizationTrialSyncJob.perform_now(organization.id, :EXTENDED, "123", {})
          end
        end

        assert_match "No Cloud Trial For Organization", logs
      end

      test "syncs a trial" do
        cloud_trial = ::Billing::EnterpriseCloudTrial.new(@organization)
        cloud_trial.extend_trial(10)

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::BusinessTrials::OrganizationTrialSyncJob.perform_now(@organization.id, :EXTENDED, "123", {})
          end
        end

        assert_match "Syncing trial to organization or business", logs
        assert_match "gh.copilot.business_trial.id=\"#{@trial.id}", logs

        @trial.reload
        assert_equal T.must(cloud_trial.expires_on).to_date, @trial.ends_at.to_date
      end
    end
  end
end if GitHub.copilot_enabled?
