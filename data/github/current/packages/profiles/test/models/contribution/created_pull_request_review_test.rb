# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionCreatedPullRequestReviewTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :rebase_pull_request)
    @pull = create(:pull_request,
      repository:      @repo,
      base_repository: @repo,
      base_user:       @repo.owner,
      base_ref:        "master",
      head_repository: @repo,
      head_user:       @repo.owner,
      head_ref:        "contrib",
    )
    @user = create(:user)
  end

  setup do
  end

  context "#organization_id" do
    test "returns the organization ID of the repository of the pull request for the PR review" do
      org_id = 123
      repo = stub(organization_id: org_id)
      pull_request = stub(repository: repo)
      pr_review = stub(pull_request: pull_request)
      contribution = Contribution::CreatedPullRequestReview.new(user: @user, subject: pr_review)
      assert_equal org_id, contribution.organization_id
    end
  end

  context "::subjects_for" do
    test "preloads the pull_request relation" do
      review = Timecop.freeze(2016, 7, 15) do
        r = create(:pull_request_review, user: @user, pull_request: @pull)
        r.approve!
        r
      end
      date_range = Date.new(2016, 7, 1)..Date.new(2016, 7, 31)
      result = Contribution::CreatedPullRequestReview.subjects_for(
        @user,
        date_range: date_range,
        lightweight: true,
      )
      assert_predicate result[0].association(:pull_request), :loaded?
    end

    test "allows filtering by organization" do
      org_a, org_b = create_pair(:organization, public_members: [@user]).each do |org|
        repo = create(:private_repository, owner: org, from_example: :encodings)
        pr = create(:pull_request, repository: repo, base_ref: "empty-branch", head_ref: "master", user: org.admins.first)

        review = create(:pull_request_review, user: @user, pull_request: pr)
        review.approve!
      end

      subjects = Contribution::CreatedPullRequestReview.subjects_for(
        @user,
        date_range: 2.days.ago.to_date..Date.tomorrow,
        organization_id: org_a.id,
        lightweight: true,
      )

      assert_same_elements org_a.repositories.first.pull_requests.first.reviews, subjects
    end

    test "excludes contributions in orgs specified by excluded_organization_ids" do
      excluded_org, other_org = create_pair(:organization, public_members: [@user]) do |org|
        repo = create(:private_repository, owner: org, from_example: :encodings)
        pr = create(:pull_request, repository: repo, base_ref: "empty-branch", head_ref: "master", user: org.admins.first)
        review = create(:pull_request_review, user: @user, pull_request: pr)
        review.approve!
      end

      subjects = Contribution::CreatedPullRequestReview.subjects_for(
        @user,
        date_range: 2.days.ago.to_date..Date.tomorrow,
        excluded_organization_ids: [excluded_org.id],
        lightweight: true,
      )

      assert_same_elements other_org.repositories.first.pull_requests.first.reviews, subjects
    end

    test "limits the number of pull request reviews to avoid performance bottlenecks" do
      review = Timecop.freeze(2016, 7, 15) do
        r = create(:pull_request_review, user: @user, pull_request: @pull)
        r.approve!
        r
      end
      date_range = Date.new(2016, 7, 1)..Date.new(2016, 7, 31)
      subjects = Contribution::CreatedPullRequestReview.subjects_for(
        @user,
        date_range: date_range,
        lightweight: true,
      )
      refute_empty subjects

      Contribution.stub_const(:DEFAULT_COUNT_LIMIT, 0) do
        subjects = Contribution::CreatedPullRequestReview.subjects_for(
          @user,
          date_range: date_range,
          lightweight: true,
        )
        assert_empty subjects
      end
    end

    test "doesn't return reviews without pull requests" do
      review = Timecop.freeze(2016, 7, 15) do
        r = create(:pull_request_review, user: @user, pull_request: @pull)
        r.approve!
        r
      end
      date_range = Date.new(2016, 7, 1)..Date.new(2016, 7, 31)

      assert_equal [review], Contribution::CreatedPullRequestReview.subjects_for(
        @user,
        date_range: date_range,
        lightweight: true,
      )

      @pull.delete
      refute_nil review.reload.pull_request_id
      assert_nil review.pull_request

      assert_empty Contribution::CreatedPullRequestReview.subjects_for(
        @user,
        date_range: date_range,
        lightweight: true,
      )
    end

    test "includes all-reply review created in time range that has a body" do
      Timecop.freeze(2016, 7, 15) do
        review = @pull.reviews.create!(user: create(:user), head_sha: @pull.head_sha)
        thread = @pull.review_threads.build(pull_request_review: review)
        thread.build_first_comment(
          body: "ship it",
          path: "README",
          line: 1,
        ).save!
        review.comment!

        reply_review = @pull.reviews.create!(
          user: @user,
          head_sha: @pull.head_sha,
          body: "hello world",
        )
        thread.build_reply(
          pull_request_review: reply_review,
          user: @user,
          body: "nice",
        ).save!
        reply_review.approve!

        date_range = Date.new(2016, 7, 1)..Date.new(2016, 7, 31)
        assert_equal [reply_review], Contribution::CreatedPullRequestReview.subjects_for(
          @user,
          date_range: date_range,
          lightweight: true,
        )
      end
    end

    test "returns the latest review by the user for a pull request" do
      old_review = Timecop.freeze(2016, 2, 12) do
        r = create(:pull_request_review, user: @user, pull_request: @pull, body: "old review")
        r.approve!
        r
      end
      new_review = Timecop.freeze(2016, 2, 24) do
        r = create(:pull_request_review, user: @user, pull_request: @pull, body: "new review")
        r.request_changes!
        r
      end
      date_range = Date.new(2016, 2, 1)..Date.new(2016, 2, 29)
      assert_equal [new_review], Contribution::CreatedPullRequestReview.subjects_for(
        @user,
        date_range: date_range,
        lightweight: true,
      )
    end

    test "includes non-pending PR review user created in time range" do
      # In time range and not pending
      review = Timecop.freeze(2016, 7, 15) do
        r = create(:pull_request_review, user: @user, pull_request: @pull)
        r.approve!
        r
      end

      # Out of time range
      Timecop.freeze(2016, 4, 8) do
        r = create(:pull_request_review, user: @user, pull_request: @pull)
        r.approve!
      end

      date_range = Date.new(2016, 7, 1)..Date.new(2016, 7, 31)
      assert_equal [review], Contribution::CreatedPullRequestReview.subjects_for(
        @user,
        date_range: date_range,
        lightweight: true,
      )
    end
  end

  context "#repository_id" do
    test "returns the id of the pull request's repository" do
      review = create(:pull_request_review, user: @user, pull_request: @pull)
      contribution = Contribution::CreatedPullRequestReview.new(user: @user, subject: review)
      assert_equal @repo.id, contribution.repository_id
    end
  end

  context "#pull_request_review" do
    test "returns the pull request review" do
      review = create(:pull_request_review, user: @user, pull_request: @pull)
      contribution = Contribution::CreatedPullRequestReview.new(user: @user, subject: review)
      assert_equal review, contribution.pull_request_review
    end
  end

  context "#pull_request" do
    test "returns the pull request" do
      review = create(:pull_request_review, user: @user, pull_request: @pull)
      contribution = Contribution::CreatedPullRequestReview.new(user: @user, subject: review)
      assert_equal @pull, contribution.pull_request
    end
  end

  context "#repository" do
    test "returns the pull request's repository" do
      review = create(:pull_request_review, user: @user, pull_request: @pull)
      contribution = Contribution::CreatedPullRequestReview.new(user: @user, subject: review)
      assert_equal @repo, contribution.repository
    end
  end

  context "#associated_subject" do
    test "returns the pull request's repository" do
      review = create(:pull_request_review, user: @user, pull_request: @pull)
      contribution = Contribution::CreatedPullRequestReview.new(user: @user, subject: review)
      assert_equal @repo, contribution.associated_subject
    end
  end

  context "#occurred_at" do
    test "returns the pull request review's submitted at" do
      Timecop.freeze(2016, 11, 4) do
        submitted_at = 3.days.ago
        review = create(:pull_request_review, user: @user, pull_request: @pull, submitted_at: submitted_at)
        contribution = Contribution::CreatedPullRequestReview.new(user: @user, subject: review)
        assert_equal submitted_at, contribution.occurred_at
      end
    end
  end

  context "#name_with_owner" do
    test "returns the repository's name with the owner" do
      review = create(:pull_request_review, user: @user, pull_request: @pull)
      contribution = Contribution::CreatedPullRequestReview.new(user: @user, subject: review)
      assert_equal @repo.name_with_display_owner, contribution.name_with_owner
    end
  end

  context "#title" do
    test "returns the rpull request's title" do
      review = create(:pull_request_review, user: @user, pull_request: @pull)
      contribution = Contribution::CreatedPullRequestReview.new(user: @user, subject: review)
      assert_equal @pull.title, contribution.title
    end
  end
end
