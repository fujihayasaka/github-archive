# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/permissions_helper"

class RevokeAllPermissionsForActorJobTest < GitHub::TestCase
  include JobTestHelper
  include PermissionsHelper

  fixtures do
    @org = create(:organization)

    @installation = make_integration_installation(target: @org, permissions: {
      "metadata" => :read, "issues" => :read, "contents" => :write, "members" => :read
    })
  end

  test "revokes all permission records for an actor" do
    perform_enqueued_jobs(only: [RevokeAllPermissionsForActorJob]) do
      RevokeAllPermissionsForActorJob.perform_later(@installation.ability_id, @installation.ability_type, :test_case)
    end

    refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @org.repository_resources.metadata)
    refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @org.repository_resources.issues)
    refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @org.repository_resources.contents)
    refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @org.resources.members)
  end

  test "can split work into batches" do
    BatchedJob.stub_const(:BATCH_SIZE, 2) do
      perform_enqueued_jobs(only: [RevokeAllPermissionsForActorJob]) do
        RevokeAllPermissionsForActorJob.perform_later(@installation.ability_id, @installation.ability_type, :test_case)
      end
    end

    refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @org.repository_resources.metadata)
    refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @org.repository_resources.issues)
    refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @org.repository_resources.contents)
    refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @org.resources.members)
  end
end
