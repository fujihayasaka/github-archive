# typed: true
# frozen_string_literal: true

require "test_helper"

class ReferrerAndReferenceableModelTest < GitHub::TestCase
  fixtures do
    @owner = create :user, login: "owner"
    @actor = create :user, login: "actor"
    @repo = create :repository, owner: @owner, name: "source", from_example: :simple
    @repo.add_member @actor
    @issue = create :issue, repository: @repo, body: "this is the target issue", create_references: true

    @review_repo = create :repository, owner: @owner, name: "review_repo", from_example: :simple
    @issue_on_review_repo = create :issue, repository: @review_repo, body: "this is the target issue", create_references: true
  end

  def make_pr(repo)
    PullRequest.create_for!(repo,
      base: "master",
      head: "cr-line-endings",
      user: @actor,
      title: "convert to CR line ending",
      body: "most valuable PR ever A++++ please do merge",
    )
  end

  [Issue, IssueComment, PullRequestReviewComment].each do |model|
    test "a #{model} can refer to an issue" do
      attrs = {
        repository: @repo,
        user: @actor,
        body: "hey check out owner/source##{@issue.number}",
      }
      if model == PullRequestReviewComment
        pull = make_pr(@repo)
        attrs[:pull_request] = pull
      elsif model == Issue
        attrs[:create_references] = true
      end

      comment = T.let(nil, T.untyped)
      assert_difference("@issue.references.count") do
        comment = perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { create(T.must(model.name).underscore.to_sym, attrs) }

        if comment.is_a?(PullRequestReviewComment)
          perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
            comment.submit!
          end
        end
      end

      source = comment.respond_to?(:issue) ? comment.issue : comment
      cross_reference = @issue.references.first
      assert_equal source, cross_reference.source
      assert_equal @issue, cross_reference.target
      assert_equal @actor, cross_reference.actor
    end
  end

  test "a PullRequestReviewComment with reviews can refer to an issue when submitted" do
    model = PullRequestReviewComment
    @review_repo.add_member(@actor)
    pull = make_pr(@review_repo)
    attrs = {
      repository: @review_repo,
      user: @actor,
      body: "hey check out owner/source##{@issue.number}",
      pull_request: pull,
    }
    comment = T.let(nil, T.untyped)
    assert_no_difference("@issue.references.count") do
      # The below code matches how we create comments / reviews via the controller,
      # currently. It is pretty horrible, but hopefully we will have it cleaned up soon so
      # that the review is created first and then the dependant comment.
      comment = build(T.must(model.name).underscore.to_sym, attrs)
      comment.add_review_for(user: @actor, pull_request: pull, head_sha: pull.head_sha)
      comment.save!
    end
    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
      assert_difference("@issue.references.count") do
        comment.pull_request_review.comment!
      end
    end
  end

end
