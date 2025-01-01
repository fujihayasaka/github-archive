# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestFindersDependencyTest < GitHub::TestCase

  include GitHub::DatabaseQueryWarningsTestHelpers

  context "drafts scope" do
    test "includes only draft pull requests" do
      draft_pull = create(:pull_request, :disable_disk_access, draft: true)
      non_draft_pull = create(:pull_request, :disable_disk_access, draft: false)

      result = PullRequest.drafts

      assert_includes result, draft_pull
      refute_includes result, non_draft_pull
    end
  end

  context "for base ref" do
    test "triggers no query warnings" do
      assert_no_query_warnings do
        repo = create :repository
        assert_empty PullRequest.for_base_ref(GRIN_EMOJI)
      end
    end
  end

  context "for head repo and head ref" do
    test "triggers no query warnings" do
      assert_no_query_warnings do
        repo = create :repository
        assert_empty PullRequest.for_head_repo_and_head_ref(repo, GRIN_EMOJI)
      end
    end
  end

end
