# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class GitBackupsTest < GitHub::TestCase
  fixtures do
    @repo = create :repository
    @staff = create :staff_admin_user
  end

  test "deleting archived repository backups" do
    @repo.remove(@repo.owner)

    GitHub::Gitbackups::Client.any_instance.expects(:delete).once.returns(:ok)
    if GitHub.flipper[:gitbackups_async_delete].enabled?
      assert_performed_with(job: GitbackupsDeleteJob, args: [@repo.repository_spec]) do
        @repo.delete_backup
      end
    else
      @repo.delete_backup
    end
  end

  test "deleting archived repository backups fails under hold" do
    @repo.remove(@repo.owner)

    GitHub::Gitbackups::Client.any_instance.expects(:delete).once.returns(:ok)

    # Give the user a legal hold so we don't actually delete the repository even
    # if it's past the stale age.
    @repo.owner.place_legal_hold(actor: @staff)
    assert_raises GitBackups::DeleteNotAllowedError do
      @repo.delete_backup
    end

    @repo.owner.clear_legal_hold(actor: @staff)
    @repo.reload

    if GitHub.flipper[:gitbackups_async_delete].enabled?
      assert_performed_with(job: GitbackupsDeleteJob, args: [@repo.repository_spec]) do
        @repo.delete_backup
      end
    else
      @repo.delete_backup
    end
  end

  test "deleting missing repositories is ok" do
    @repo.remove(@repo.owner)

    GitHub::Gitbackups::Client.any_instance.expects(:delete).with(@repo.repository_spec).returns(:not_found)

    if GitHub.flipper[:gitbackups_async_delete].enabled?
      assert_performed_with(job: GitbackupsDeleteJob, args: [@repo.repository_spec]) do
        @repo.delete_backup
      end
    else
      @repo.delete_backup
    end
  end
end
