# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::PurgeSoftDeletedCodespacesJobTest < GitHub::TestCase
  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  test "destroys codespaces that have been deleted for more than X days" do
    GitHub.flipper[:codespaces_pause_deletions_user_requested].disable
    create(:codespace)

    old_deleted_codespace = create(:codespace)
    old_deleted_codespace.deprovisioning!
    assert old_deleted_codespace.soft_delete
    old_deleted_codespace.update!(deleted_at: 10.days.ago)

    recently_deleted_codespace = create(:codespace)
    recently_deleted_codespace.deprovisioning!
    assert recently_deleted_codespace.soft_delete
    recently_deleted_codespace.update!(deleted_at: 1.day.ago)

    assert_equal 1, Codespace.count
    assert_equal 2, Codespace.deleted.count
    Codespaces::PurgeSoftDeletedCodespacesJob.perform_now
    assert_equal 1, Codespace.count
    assert_equal 1, Codespace.deleted.count
    assert_equal recently_deleted_codespace, Codespace.deleted.last
    assert_equal 1, GitHub.dogstats.increments("codespaces_purged.count").count
  end

  test "keeps going even if there is an error deleting one of the codespaces" do
    GitHub.flipper[:codespaces_pause_deletions_user_requested].disable
    create(:codespace)

    old_deleted_codespace = create(:codespace)
    old_deleted_codespace.deprovisioning!
    assert old_deleted_codespace.soft_delete
    old_deleted_codespace.update!(deleted_at: 10.days.ago)

    other_deleted_codespace = create(:codespace)
    other_deleted_codespace.deprovisioning!
    assert other_deleted_codespace.soft_delete
    other_deleted_codespace.update!(deleted_at: 10.days.ago)

    assert_equal 1, Codespace.count
    assert_equal 2, Codespace.deleted.count

    Codespace.any_instance.stubs(:destroy_requires_deprovisioning).raises(StandardError.new("boom")).returns(nil)
    Codespaces::PurgeSoftDeletedCodespacesJob.perform_now
    assert_equal 1, Codespace.count
    assert_equal 1, Codespace.deleted.count
    assert_equal 1, GitHub.dogstats.increments("codespaces_purged.count").count
  end
end
