# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestConflictTest < GitHub::TestCase
  fixtures do
    repo = create(:repository)
    @pull_request = create(:pull_request, :disable_disk_access, repository: @repo)
  end

  test "copies `repository_id` from the `pull_request` during create" do
    pull_request_conflict = PullRequestConflict.create(pull_request: @pull_request, base_sha: SecureRandom.hex(20), head_sha: SecureRandom.hex(20))

    refute_nil pull_request_conflict.repository_id
    assert_equal pull_request_conflict.repository_id, @pull_request.repository_id
  end
end
