# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::LicenseSnapshotForExpiredRepositoryInvitationsJobTest < GitHub::TestCase
  include HydroTestHelpers

  test "take a snapshot to expired invitation" do
    inviter = create(:user)
    invitee = create(:user)
    business = create(:business)
    organization = create(:organization, business: business)
    repository = create(:private_repository, owner: organization)
    invitation = RepositoryInvitation.create(
      repository: repository,
      inviter: inviter,
      invitee: invitee,
      permissions: 1,
    )

    assert_enqueued_jobs 1, only: Licensing::SnapshotLicensesJob do
      Timecop.travel(Time.now + 8.days) do
        Licensing::LicenseSnapshotForExpiredRepositoryInvitationsJob.perform_now
      end
    end
  end
end
