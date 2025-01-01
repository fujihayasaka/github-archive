# typed: true
# frozen_string_literal: true

require "test_helper"

class ReviewRequestAssociationExtensionTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @org = create(:organization, admin: @owner)
    @team = create(:team, organization: @org, privacy: :closed)
    @forker = create(:user)
    @rando = create(:user)

    @org.allow_private_repository_forking(actor: @org.admins.first)

    @source = create(:private_repository, owner: @org, name: "source", from_example: :review_comment_fork)
    @source.add_team @team, action: :write
    @source.add_member @forker, action: :write

    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)

    @protected_branch = create(:protected_branch, repository: @source, creator: @owner)

    @issue = create(:issue, user: @forker, repository: @source)
    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @issue,
        user: @forker,
      )
    @issue.pull_request = @pull
  end

  context "#pending_reviewers=" do
    test "builds review requests for the passed reviewers" do
      @pull.review_requests.pending_reviewers = [@owner, @team]

      assert @pull.review_requests.all?(&:new_record?)
      assert_equal 2, @pull.review_requests.size
      assert_equal [@owner, @team], @pull.review_requests.map(&:reviewer)
    end

    test "saves the built review requests when the pull is saved" do
      @pull.review_requests.pending_reviewers = [@owner, @team]
      @pull.save!

      assert @pull.review_requests.all?(&:persisted?)
      assert_equal 2, @pull.review_requests.size
      assert_equal [@owner, @team], @pull.review_requests.map(&:reviewer)
    end

    test "ignores reviewers who aren't allowed to be requested" do
      @pull.review_requests.pending_reviewers = [@owner, @rando]

      assert_equal 1, @pull.review_requests.size
      assert_equal [@owner], @pull.review_requests.map(&:reviewer)
    end

    test "doesn't overwrite existing requests if specified" do
      existing = @pull.review_requests.create!(reviewer: @owner)
      @pull.review_requests.pending_reviewers = [@owner, @team]

      assert_equal 2, @pull.review_requests.size
      assert_includes @pull.review_requests, existing
    end

    test "dismisses existing requests on save if not specified" do
      existing = @pull.review_requests.create!(reviewer: @owner)
      @pull.review_requests.pending_reviewers = [@team]

      assert_equal 2, @pull.review_requests.size

      @pull.save!

      assert_equal 1, @pull.review_requests.reload.count
      refute_includes @pull.review_requests, existing

      existing.reload
      assert_predicate existing, :dismissed?
    end

    test "allows removing code owner requests if owner reviews aren't required" do
      @protected_branch.update_column :require_code_owner_review, false

      owner_request = @pull.review_requests.add_pending_reviewer_with_reasons(@owner, reasons: {
        codeowners: [
          { tree_oid: "725a9899207f0b65f51f27dba5eb77822edaf740", path: "CODEOWNERS", line: 42, pattern: "*" },
          { tree_oid: "725a9899207f0b65f51f27dba5eb77822edaabcd", path: "CODEOWNERS", line: 60, pattern: "*.js" },
        ],
      })
      owner_request.save!

      assert_includes @pull.reload.review_requests.reviewers, @owner

      @pull.review_requests.pending_reviewers = [@team]
      @pull.save!

      refute_includes @pull.reload.review_requests.reviewers, @owner
    end

    test "does NOT allow removing code owner requests if owner reviews are required and user is valid codeowner" do
      @protected_branch.enable_required_pull_request_reviews(require_code_owner_reviews: true)
      @protected_branch.save
      Repository::Codeowners.any_instance.stubs(:include?).with { |_reviewer| true }.returns(true)

      owner_request = @pull.review_requests.add_pending_reviewer_with_reasons(@owner, reasons: {
        codeowners: [
          { tree_oid: "725a9899207f0b65f51f27dba5eb77822edaf740", path: "CODEOWNERS", line: 42, pattern: "*" },
          { tree_oid: "725a9899207f0b65f51f27dba5eb77822edaabcd", path: "CODEOWNERS", line: 60, pattern: "*.js" },
        ],
      })
      owner_request.save!

      assert_includes @pull.reload.review_requests.reviewers, @owner

      @pull.review_requests.pending_reviewers = [@team]
      @pull.save!

      assert_includes @pull.reload.review_requests.reviewers, @owner
    end
  end

  context "#add_pending_reviewer_with_reasons" do
    test "builds a new review request and reasons" do
      @pull.review_requests.add_pending_reviewer_with_reasons(@owner, reasons: {
        codeowners: [
          { tree_oid: "725a9899207f0b65f51f27dba5eb77822edaf740", path: "CODEOWNERS", line: 42, pattern: "*" },
          { tree_oid: "725a9899207f0b65f51f27dba5eb77822edaabcd", path: "CODEOWNERS", line: 60, pattern: "*.js" },
        ],
      })

      assert_equal 1, @pull.review_requests.size
      assert request = @pull.review_requests.first
      assert_predicate request, :new_record?
      refute_predicate request, :deferred?
      assert_equal @owner, request.reviewer

      assert_equal 2, request.reasons.size
      assert request.reasons.all?(&:new_record?)
      assert reason = request.reasons.first
      assert_equal "725a9899207f0b65f51f27dba5eb77822edaf740", reason.codeowners_tree_oid
      assert_equal "CODEOWNERS", reason.codeowners_path
      assert_equal 42, reason.codeowners_line
      assert_equal "*", reason.codeowners_pattern
    end

    test "saves the request and reasons when the PR is saved" do
      @pull.review_requests.add_pending_reviewer_with_reasons(@owner, reasons: {
        codeowners: [
          { tree_oid: "725a9899207f0b65f51f27dba5eb77822edaf740", path: "CODEOWNERS", line: 42, pattern: "*" },
          { tree_oid: "725a9899207f0b65f51f27dba5eb77822edaabcd", path: "CODEOWNERS", line: 60, pattern: "*.js" },
        ],
      })
      @pull.save!

      assert_equal 1, @pull.review_requests.size
      assert request = @pull.review_requests.first
      assert_predicate request, :persisted?

      assert_equal 2, request.reasons.size
      assert request.reasons.all?(&:persisted?)
    end

    test "doesn't add reviewer if not allowed to request them" do
      refute @pull.review_requests.add_pending_reviewer_with_reasons(@rando, reasons: {
        codeowners: [
          { tree_oid: "725a9899207f0b65f51f27dba5eb77822edaf740", path: "CODEOWNERS", line: 42, pattern: "*" },
          { tree_oid: "725a9899207f0b65f51f27dba5eb77822edaabcd", path: "CODEOWNERS", line: 60, pattern: "*.js" },
        ],
      })

      assert_equal 0, @pull.review_requests.size
    end
  end

  context "copilot" do
    test "allows review bot when app is enabled" do
      create(:copilot_pull_request_reviewer_integration)
      review_bot = Apps::Privileged.integration(:copilot_pull_request_reviewer).bot
      @pull.review_requests.pending_reviewers = [review_bot]

      assert @pull.review_requests.all?(&:new_record?)
      assert_equal 1, @pull.review_requests.size
      assert_equal [review_bot], @pull.review_requests.map(&:reviewer)
    end
  end
end
