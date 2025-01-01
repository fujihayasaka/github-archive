# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::Billing::CleanupNonEmittingOrgsJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "perform" do
    test "it will do nothing if flag is disabled" do
      disable_feature_flag(:copilot_seat_emission_job)

      assert_logged("Body" => "Skipping Copilot::Billing::CleanupNonEmittingOrgsJob") do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::Billing::CleanupNonEmittingOrgsJob.perform_now
        end
      end
    end

    test "it finds all orgs that are not emitting and passes them to Copilot::Billing::OrganizationSeatEmissionJob" do
      freeze_time do
        enable_feature_flag(:copilot_seat_emission_job)

        # an organization with a seat and seat emissions in the last day is considered emitting
        emitting_seat = create(:copilot_seat)
        emitting_org = emitting_seat.organization
        create(:copilot_seat_emission, owner: emitting_org, occurred_at: 1.hour.ago)

        # an organization with a seat, but no seat emissions is consider non-emitting
        non_emitting_seat = create(:copilot_seat)
        non_emitting_org = non_emitting_seat.organization

        # an organization with a seat in a CFB trial shouldn't count
        trial = create(:copilot_business_trial, :organization)
        trial_org = trial.trialable
        create(:copilot_seat, organization: trial_org)

        Copilot::Billing::OrganizationSeatEmissionJob.expects(:perform_later).with(non_emitting_org.id).once
        Copilot::Billing::OrganizationSeatEmissionJob.expects(:perform_later).with(emitting_org.id).never
        Copilot::Billing::OrganizationSeatEmissionJob.expects(:perform_later).with(trial_org.id).never

        expected_log = {
          "Body" => "Non-emitting org found. Passing to OrganizationSeatEmissionJob",
          "code.namespace" => "Copilot::Billing::CleanupNonEmittingOrgsJob",
          "code.function" => "perform",
          "gh.org.id" => non_emitting_org.id,
        }
        assert_logged("Body" => "Finding non-emitting orgs") do
          assert_logged(**expected_log) do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::Billing::CleanupNonEmittingOrgsJob.perform_now
            end
          end
        end
      end
    end
  end
end if GitHub.copilot_enabled?
