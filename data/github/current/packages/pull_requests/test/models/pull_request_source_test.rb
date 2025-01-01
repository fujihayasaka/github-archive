# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestSourceTest < GitHub::TestCase
  test "sets `repository_id` from the pull" do
    pull_request = create(:pull_request, :disable_disk_access)
    pull_request.pull_request_sources.create(source: :codespace)
    pull_request_source = pull_request.pull_request_sources.first

    refute_nil pull_request_source.repository_id
    assert_equal pull_request_source.repository_id, pull_request.repository_id
  end
end
