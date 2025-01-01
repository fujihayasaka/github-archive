# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryArchivedDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)

    @org = create(:organization, admin: @user, plan: GitHub::Plan.free)

    perform_enqueued_jobs only: Organizations::ArchiveJob do
      @org.archive(@user)
    end

    @repository = create(:archived_repository, owner: @org)
  end

  setup do
    @repository.stubs(:actor).returns(@user)
  end

  test "cannot unarchive repo in archived organization" do
    assert @org.archived?
    refute @repository.unset_archived(synchronous: true)
    assert @repository.archived?
  end
end
