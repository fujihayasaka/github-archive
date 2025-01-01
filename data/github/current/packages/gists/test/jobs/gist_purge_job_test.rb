# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class GistPurgeJobTest < GitHub::TestCase
  include JobTestHelper
  include GistTestHelper

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: GistPurgeJob
  end

  test "purge deleted gists" do
    Gist.any_instance.stubs(:delete_backup).returns(nil)
    user = create(:verified_user)
    user2 = create(:verified_user)
    user2.place_legal_hold(actor: @staff)

    # GistTestHelper creates a soft-deleted gist for some reason
    assert_equal 1, Gist.deleted.count
    existing = Gist.deleted.first!
    # Make sure this existing gist isn't seen as a failed creation
    existing.update_column(:pushed_count, 1)

    gist1 = generate_deleted_gist(user, 80.days.ago)
    gist2 = generate_deleted_gist(user, 100.days.ago)
    gist3 = generate_deleted_gist(user2, 80.days.ago)
    gist4 = generate_deleted_gist(user2, 100.days.ago)

    gist1_updated_at = gist1.updated_at.to_i
    gist3_updated_at = gist3.updated_at.to_i
    gist4_updated_at = gist4.updated_at.to_i

    assert_equal 5, Gist.deleted.count

    # gist2 should be purged, the rest should stay soft_deleted
    GistPurgeJob.perform_now

    assert_equal 4, Gist.deleted.count

    assert_equal gist1_updated_at, gist1.reload.updated_at.to_i # left alone
    assert_equal gist3_updated_at, gist3.reload.updated_at.to_i # left alone
    assert gist4_updated_at.to_i < gist4.reload.updated_at.to_i # touched

    assert_same_elements [T.must(existing).id, gist1.id, gist3.id, gist4.id], Gist.deleted.pluck(:id)

    GistPurgeJob.perform_now
  end

  test "purge failed creations" do
    Gist.any_instance.stubs(:delete_backup).returns(nil)
    user = create(:verified_user)

    # GistTestHelper creates a soft-deleted gist for some reason
    assert_equal 1, Gist.deleted.count
    existing = Gist.deleted.first
    existing&.update_column(:pushed_count, 1)

    gist1 = generate_deleted_gist(user, 80.days.ago)
    gist2 = generate_deleted_gist(user, 100.days.ago)

    failed_creation_gist1 = generate_failed_creation_gist(user, 10.days.ago)
    failed_creation_gist2 = generate_failed_creation_gist(user, 2.hours.ago)
    failed_creation_gist3 = generate_failed_creation_gist(user, 1.minute.ago)

    assert_equal 6, Gist.deleted.count

    # gist2 and failed_creation_gist2 should be purged, the rest should stay soft_deleted
    GistPurgeJob.perform_now

    assert_nil Gist.find_by(id: gist2.id)
    assert_nil Gist.find_by(id: failed_creation_gist2.id)
    assert_same_elements [T.must(existing).id, gist1.id, failed_creation_gist1.id, failed_creation_gist3.id], Gist.deleted.pluck(:id)
  end

  test "purging failed creations respects max batch size" do
    Gist.any_instance.stubs(:delete_backup).returns(nil)
    user = create(:verified_user)

    # GistTestHelper creates a soft-deleted gist for some reason
    assert_equal 1, Gist.deleted.count
    existing = Gist.deleted.first!
    existing.update_column(:pushed_count, 1)

    gist1 = generate_deleted_gist(user, 80.days.ago)
    gist2 = generate_deleted_gist(user, 100.days.ago)

    failed_creation_gist1 = generate_failed_creation_gist(user, 10.days.ago)
    failed_creation_gist2 = generate_failed_creation_gist(user, 1.hour.ago)

    assert_equal 5, Gist.deleted.count

    # Only gist2 will be purged, since the batch size only allows 1
    GistPurgeJob.perform_now(1)

    assert_nil Gist.find_by(id: gist2.id)
    assert_same_elements [T.must(existing).id, gist1.id, failed_creation_gist1.id, failed_creation_gist2.id], Gist.deleted.pluck(:id)
  end

  def generate_deleted_gist(user, updated_at)
    gist = T.let(nil, T.untyped)
    perform_enqueued_jobs(only: [GistPushJob]) do
      gist = GistHelpers.generate(contents: gist_test_content_array, user: user)
    end
    gist.remove
    gist.update_column(:updated_at, updated_at)
    gist
  end

  def generate_failed_creation_gist(user, updated_at)
    gist = T.let(nil, T.untyped)
    gist = GistHelpers.generate(contents: gist_test_content_array, user: user)
    gist.remove
    gist.update_column(:updated_at, updated_at)
    gist.update_column(:created_at, updated_at)
    gist
  end
end
