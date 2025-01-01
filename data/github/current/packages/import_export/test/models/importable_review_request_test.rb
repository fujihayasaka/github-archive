# typed: true
# frozen_string_literal: true

require "test_helper"

class ImportableReviewRequestTest < GitHub::TestCase
  fixtures do
    repo = create(:importable_repository).tap do |repo|
      example_repo :pull_request_source, repo
      head_ref = repo.heads.create("topic", repo.heads.find("master").target, repo.owner)
      head_ref.append_commit({ message: "a change", committer: repo.owner }, repo.owner) do |files|
        files.add("README.txt", "one\ntwo\nthree\n")
      end
      @repo = Repository.find_by(id: repo.id)
    end
    @pull = create(:importable_pull_request,
                   repository: @repo,
                   base_repository: @repo,
                   head_repository: @repo,
                   base_ref: "master",
                   head_ref: "topic",
                   base_user: @repo.owner,
                   head_user: @repo.owner,
                   base_sha: @repo.heads["master"].sha,
                   head_sha: @repo.heads["topic"].sha,
                   )
    @review_request = create(:importable_review_request, pull_request: @pull)
  end

  test "has ReviewRequest type" do
    assert_equal "ReviewRequest", @review_request.type
  end

  context "#importing?" do
    test "#importing? returns true during import context" do
      assert @review_request.importing?
    end

    test "#importing? returns false outside of import context" do
      non_import_review_request = ReviewRequest.find(@review_request.id)
      non_import_review_request.importing?
    end
  end

  context "skipped validations" do
    test "skips validations for imported review request" do
      @review_request.expects(:ensure_requested_team_is_in_valid_org).never
      @review_request.expects(:ensure_requested_reviewer_is_a_collaborator).never
      @review_request.expects(:trigger_review_requested_event).never
      @review_request.expects(:trigger_review_request_removed_event).never
    end
  end
end
