# typed: true
# frozen_string_literal: true

require "test_helper"

class LastSeenPullRequestRevisionTest < GitHub::TestCase
  fixtures do
    repo = create(:repository)
    @user = create(:user)
    @pull_request = create(:pull_request, :disable_disk_access, repository: @repo)
  end

  test "copies `repository_id` from the `pull_request` during create" do
    last_seen_pull_request_revision = LastSeenPullRequestRevision.create(pull_request: @pull_request, user_id: @user.id, last_revision: "abc")

    refute_nil last_seen_pull_request_revision.repository_id
    assert_equal last_seen_pull_request_revision.repository_id, @pull_request.repository_id
  end
end
