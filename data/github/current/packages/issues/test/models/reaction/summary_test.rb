# typed: true
# frozen_string_literal: true

require "test_helper"

class ReactionSummaryTest < GitHub::TestCase
  test "prefill counts" do
    repo = create(:repository, from_example: :pull_request_source)

    user   = repo.owner
    author = create :user, login: "author"

    branch = repo.heads.create("patch", repo.heads.find("master").target, user)
    commit = branch.append_commit({ message: "change", committer: user }, user) do |f|
      f.add("change.txt", "foo")
    end

    pull = create(:pull_request,
      repository: repo,
      base_repository: repo,
      base_user: user,
      base_ref: "master",
      head_repository: repo,
      head_user: user,
      head_ref: "patch",
      issue: create(:issue, repository: repo, user: user),
    )

    issue_comment = create(:issue_comment, issue: pull.issue)
    issue_comment_without_reactions = create(:issue_comment, issue: pull.issue)
    commit_comment = create(:commit_comment, commit_id: commit.oid, repository: repo)
    review_comment = create(:pull_request_review_comment, pull_request: pull, user: user)
    items_to_prefill = [issue_comment, issue_comment_without_reactions, commit_comment, review_comment]

    issue_comment.react(actor: user, content: "heart")
    issue_comment.react(actor: author, content: "heart")
    issue_comment.react(actor: author, content: "+1")

    commit_comment.react(actor: user, content: "smile")
    review_comment.react(actor: user, content: "-1")

    # This should not be prefilled, but it also shouldn't cause an error.
    issue_event = create(:issue_event, issue: pull.issue, event: "mentioned")

    Reaction::Summary.prefill(items_to_prefill + [issue_event])

    # all but the issue_event should have a reactions_count
    loaded_reaction_counts = items_to_prefill.select(&:reactions_count)
    assert_equal 4, loaded_reaction_counts.size

    items_to_prefill.each do |item|
      refute item.association(:reactions).loaded?
    end

    assert_equal 2, issue_comment.reactions_count["heart"]
    assert_equal 1, issue_comment.reactions_count["+1"]
    assert_equal 1, commit_comment.reactions_count["smile"]
    assert_equal 1, review_comment.reactions_count["-1"]
  end

end
