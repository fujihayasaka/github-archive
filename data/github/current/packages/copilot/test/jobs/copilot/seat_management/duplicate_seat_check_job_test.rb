# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::SeatManagement::DuplicateSeatCheckJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    GitHub.flipper[:copilot_organization_deduplicate_job].enable
  end

  context "perform" do
    test "calls OrganizationDeduplicateJob only with orgs with duplicates" do
      duped_user = create(:user)
      organization_with_dupe = create(:organization)
      organization_with_dupe.add_member(duped_user)
      create(:copilot_seat, organization: organization_with_dupe, assigned_user: duped_user)

      # Bypassing validations to be able to create duplicates
      duped_sa = build(:copilot_seat_assignment, :user, organization: organization_with_dupe, assignable: duped_user)
      duped_sa.save(validate: false)
      create(:copilot_seat, organization: organization_with_dupe, assigned_user: duped_user, seat_assignment: duped_sa)

      non_duped_user = create(:user)
      organization_without_dupe = create(:organization)
      organization_without_dupe.add_member(non_duped_user)
      create(:copilot_seat, organization: organization_without_dupe, assigned_user: non_duped_user)

      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization_with_dupe.id).once
      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization_without_dupe.id).never

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::DuplicateSeatCheckJob.perform_now
      end
    end
  end
end if GitHub.copilot_enabled?
