# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroDeleteRestorableRepositoryMembershipsRepositoryTransferredJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @queue = "hydro_delete_restorable_repository_memberships_repository_transferred"
    @schema = "github.repositories.v1.Transferred"
  end

  test "deletes Restorable::Memberships associated with only with given repository" do
    restorable_org_user = create(:restorable_organization_user)
    restorable = restorable_org_user.restorable
    org = restorable_org_user.organization

    repo1 = create(:repository, owner: org)
    repo2 = create(:repository, owner: org)

    restorable.memberships.create({
      subject_type: "Repository",
      subject_id: repo1.id,
      action: :admin,
    })
    restorable.memberships.create({
      subject_type: "Repository",
      subject_id: repo2.id,
      action: :admin,
    })
    restorable.memberships.create({
      subject_type: "Organization",
      subject_id: org.id,
      action: :admin,
    })

    assert_equal 1, Restorable::Membership.organization_memberships.count
    assert_equal 2, Restorable::Membership.repository_memberships.count

    perform_hydro_message_job({ repository_id: repo1.id }, schema: @schema, queue: @queue)

    assert_equal 1, Restorable::Membership.organization_memberships.count
    assert_equal 1, Restorable::Membership.repository_memberships.where(subject_id: repo2.id).count
    assert_equal 0, Restorable::Membership.repository_memberships.where(subject_id: repo1.id).count
  end
end
