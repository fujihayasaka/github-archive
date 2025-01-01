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
      enable_feature_flag(:check_reference_exists)
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

      # Check that the job isn't enqueued for subsequent updates (already exists for a single reference)
      assert_enqueued_jobs 0, only: ProcessMentionedReferencesJob do
        comment.update!(**attrs.except(:create_references))
      end

      source = comment.respond_to?(:issue) ? comment.issue : comment
      cross_reference = @issue.references.first
      assert_equal source, cross_reference.source
      assert_equal @issue, cross_reference.target
      assert_equal @actor, cross_reference.actor
    end
  end

  test "batched creation of references" do
    issues = T.let([], T::Array[Issue])
    issue = T.let(nil, T.nilable(Issue))
    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
      1..10.times do
        issues << create(:issue, repository: @repo, user: @actor, create_references: true)
      end

      issue = create(:issue, repository: @repo, user: @actor, create_references: true)
    end

    issue = T.must(issue)

    # Our batched insert only hits the cross references table once (existing records are skipped)
    assert_query_count_per_table({ cross_references: 1 }) do
      perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
        # Update the issue, creating references to other issues
        issue.update!(body: issues.map { |i| "Checkout owner/source##{i.number}" }.join("\n"))
      end
    end

    cross_references = issues.first&.references || []

    assert_equal 1, cross_references.count

    cross_reference = T.must(cross_references.first)
    assert_equal issues.first, cross_reference.target
    assert_equal issue, cross_reference.source
    assert_equal @actor, cross_reference.actor

    assert_equal issues.length, issue.mentioned_referenceables.count
  end


  test "only filters out existing references" do
    issues = T.let([], T::Array[Issue])
    issue = T.let(nil, T.nilable(Issue))

    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
      1..10.times do
        issues << create(:issue, repository: @repo, user: @actor, create_references: true)
      end

      # Create a new issue with a single reference (issue 1)
      issue = create(
        :issue,
        repository: @repo,
        user: @actor,
        create_references: true,
        body: "Checkout owner/source##{T.must(issues.first).number}"
      )
    end

    issue = T.must(issue)

    assert_equal 1, issue.mentioned_referenceables.count

    # Our batched insert only hits the cross references table once (existing records are skipped)
    assert_query_count_per_table({ cross_references: 1 }) do
      perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
        # Update the issue, creating references to other issues
        issue.update!(body: issues.map { |i| "Checkout owner/source##{i.number}" }.join("\n"))
      end
    end

    issues.map do |i|
      cross_references = i.references

      assert_equal 1, cross_references.count

      cross_reference = cross_references.first!
      assert_equal i, cross_reference.target
      assert_equal issue, cross_reference.source
      assert_equal @actor, cross_reference.actor
    end

    assert_equal issues.length, issue.mentioned_referenceables.count
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
