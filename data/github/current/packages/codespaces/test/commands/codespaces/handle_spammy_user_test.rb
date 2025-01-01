# typed: true
# frozen_string_literal: true

require "test_helper"

class HandleSpammyUserTest < GitHub::TestCase
  test "deprovision user's codespaces" do
    user = create(:user)

    waiting_period = Codespaces::CleanupSpammyOwnerCodespacesJob::SPAMMY_USER_DEPROVISIONING_WAITING_PERIOD
    Codespaces::CleanupSpammyOwnerCodespacesJob.expects(:perform_after_waiting_period).with(waiting_period: waiting_period, owner_id: user.id, owner_type: user.type)
    Codespaces::HandleSpammyUser.call(user_id: user.id, user_type: user.type)
  end

  test "deprovision user's provisioning/failed codespaces" do
    user = create(:user)

    Codespaces::DeleteDependentNeverAvailableCodespacesJob.expects(:perform_later).with(owner_id: user.id)
    Codespaces::HandleSpammyUser.call(user_id: user.id, user_type: user.type)
  end

  test "will suspend user's codespaces" do
    user = create(:user)

    Codespaces::SuspendDependentCodespacesJob.expects(:perform_later).with(owner_id: user.id)
    Codespaces::HandleSpammyUser.call(user_id: user.id, user_type: user.type)
  end

  test "will suspend orgs's codespaces" do
    org = create(:organization)

    Codespaces::SuspendDependentCodespacesJob.expects(:perform_later).with(owner_id: org.id)
    Codespaces::HandleSpammyUser.call(user_id: org.id, user_type: org.type)
  end
end
