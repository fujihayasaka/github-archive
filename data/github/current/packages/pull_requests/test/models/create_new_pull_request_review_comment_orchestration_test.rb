# typed: true
# frozen_string_literal: true

require "test_helper"

class CreateNewPullRequestReviewCommentOrchestrationTestBase < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @user = create(:user, login: "mona")
    @repo = create(:repository, owner: @user, from_example: :review_comment_source)
    @forker = create(:user, login: "bwalsh")
    forked = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :review_comment_fork)
    @repo.add_member @forker

    @issue = create(:issue, user: @forker, repository: @repo)
    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: forked,
      head_user: forked.owner,
      head_ref: "topic",
      issue: @issue,
      user: @forker,
    )
    @issue.pull_request = @pull
    @review = @pull.reviews.create!(
      user: @user,
      head_sha: @pull.head_sha,
    )
  end

  sig do
    params(
      repository: Repository,
      pull_request: PullRequest,
      author: User,
      body: String,
      diff_start_commit_oid: T.nilable(String),
      diff_end_commit_oid: T.nilable(String),
      diff_base_commit_oid: T.nilable(String),
      line: T.nilable(Integer),
      path: String,
      review: PullRequestReview,
      side: Symbol,
      start_line: T.nilable(Integer),
      start_side: Symbol,
      subject_type: Symbol,
      submit_review: T::Boolean,
      stop_after_step: T.nilable(Symbol),
    ).returns([CreateNewPullRequestReviewCommentOrchestration, T.nilable(Exception)])
  end
  def execute_orchestrator!(
    repository: @repo,
    pull_request: @pull,
    author: @user,
    body: "new comment",
    diff_start_commit_oid: @pull.base_sha,
    diff_end_commit_oid: @pull.head_sha,
    diff_base_commit_oid: @pull.merge_base,
    line: 18,
    path: "aquaman.txt",
    review: @review,
    side: :right,
    start_line: nil,
    start_side: :right,
    subject_type: :line,
    submit_review: false,
    stop_after_step: nil
  )
    if stop_after_step
      CreateNewPullRequestReviewCommentOrchestration.stop_after_step = stop_after_step
    end

    orchestrator = CreateNewPullRequestReviewCommentOrchestration.create(
      # the repository and pull request need to be the same as the ones that
      # are associationed to the thread and comment created by the orchestration
      # in order for the orchestration's own database queries and persistence
      # to work
      repository: repository,
      pull_request: pull_request,
      actor: author,
      body:,
      diff_start_commit_oid:,
      diff_end_commit_oid:,
      diff_base_commit_oid:,
      line:,
      path:,
      review:,
      side:,
      start_line:,
      start_side:,
      subject_type:,
      submit_review:,
    )

    exception = T.let(nil, T.nilable(Exception))

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      begin
        orchestrator.execute!
      rescue Orchestration::Error => e
        exception = e
      end
    end

    [orchestrator.tap(&:reload), exception]
  ensure
    CreateNewPullRequestReviewCommentOrchestration.stop_after_step = nil
  end
end

class CreateNewPullRequestReviewCommentOrchestrationTest < CreateNewPullRequestReviewCommentOrchestrationTestBase
  test "create orchestration creates a new comment from the given arguments" do
    orchestrator, _ = execute_orchestrator!(
      path: "aquaman.txt",
      body: "new comment",
      line: 24,
    )

    comment = orchestrator.comment
    thread = orchestrator.thread

    assert_predicate thread, :persisted?
    assert_predicate comment, :persisted?

    assert_equal :succeeded, orchestrator.state.to_sym
    assert_equal "new comment", comment.body
    assert_equal "aquaman.txt", thread.path
    assert_equal 24, thread.line
  end

  test "computes context lines if the comment_outside_the_diff feature is enabled" do
    GitHub.flipper[:comment_outside_the_diff].enable(@pull.head_repository)

    orchestrator, _ = execute_orchestrator!(stop_after_step: :compute_context_lines)

    assert_equal orchestrator.context_lines, { "aquaman.txt" => [14..24] }
  end

  test "validates the merge base" do
    # TODO: This should be tests for the Params class.
    orchestrator, _ = execute_orchestrator!(stop_after_step: :validate_merge_base)
    assert_equal orchestrator.merge_base, @pull.merge_base
  end

  test "skips full execution if the merge base cannot be set" do
    @pull.expects(:merge_base).returns(nil).twice

    orchestrator, _ = execute_orchestrator!(stop_after_step: :validate_orchestration_can_proceed)

    assert_equal :skipped, orchestrator.state.to_sym
    assert_equal orchestrator.error_message, "Unable to compute merge base for pull request with id: #{@pull.id}"
    assert_equal :validate_orchestration_can_proceed, orchestrator.step_name&.to_sym
  end

  test "validates the pull request's head repository" do
    # TODO: This likely should also be moved to the Params class somehow
    orchestrator, _ = execute_orchestrator!(stop_after_step: :build_cotext)
    assert_equal orchestrator.head_repository, @pull.head_repository
  end

  test "skips full execution if the head repository does not exist" do
    @pull.expects(:head_repository).returns(nil).once

    orchestrator, _ = execute_orchestrator!(stop_after_step: :validate_orchestration_can_proceed)

    assert_equal :skipped, orchestrator.state.to_sym
    assert_equal orchestrator.error_message, "No head repository for pull request with id: #{@pull.id}"
    assert_equal :validate_orchestration_can_proceed, orchestrator.step_name&.to_sym
  end

  test "prepares the diff" do
    orchestrator, _ = execute_orchestrator!(stop_after_step: :build_diff)

    assert orchestrator.diff
  end

  test "creates a thread" do
    orchestrator, _ = execute_orchestrator!(stop_after_step: :build_thread)
    thread = orchestrator.thread

    assert thread
    assert_equal thread.pull_request, @pull
    assert_equal thread.pull_request_review, @review
  end

  test "creates a comment" do
    orchestrator, _ = execute_orchestrator!(stop_after_step: :persist_comment)
    comment = orchestrator.comment
    thread = orchestrator.thread

    assert comment
    assert_equal comment.pull_request_review_thread, thread
    assert_equal comment.pull_request, @pull
    assert_predicate comment, :pending?
    assert_equal comment.repository, @repo
  end

  # ------------------------------------------------------------
  #### Thread tests
  # ------------------------------------------------------------

  test "evaluates validates a thread's compressed diff hunk as invalid when it does not meet encoding requirements" do
    PullRequestReviewThread.any_instance.stubs(:compressed_diff_hunk)
      .returns("@@ -15,24 +15,26 @@ Comic Books — the first version of Aquaman" + "\x80\x81")

    orchestrator, _ = execute_orchestrator!

    assert_equal :skipped, orchestrator.state.to_sym
    refute_predicate orchestrator.thread, :persisted?
  end

  test "evaluates a thread's compressed diff hunk as valid when it includes emojis" do
    repo = create(:repository, owner: @user, from_example: :simple)

    content = <<-CONTENTS
      # GitHub Gitbus Busbus 🚌
      [![test](stuff)]
       A Ruby Gem for using a gem
      ## About 💡
      This library wraps the [Bus Gem](github/git-bus-gem) to add its own functionality and to provide an API that is more geared to how we use a Bus as a bus.
      The main class is `GitHub::GitBus::Buses::Busbus` which gets created with configuration passed to it. The main way to control the behavior of your event bus is via its configuration: `GitHub::GitBus::Buses::BusConfiguration`.
      ## Usage 💻
      This section goes into usage examples on how this Gem can be used for both Busbus **publishers** and **consumers** alike
      ### Gem Installation
      Regardless if you are using a consumer or a publisher, you will need to include this Gem in your `Gemfile`. We host this Gem in the GitHub Package Registry and it can be installed in projects like so:
      ```ruby
        source \"https://rubygems.pkg.github.com/github\" do
         gem \"github_busbusbus_extensions\", \"X.X.X\"
        end
      ```
      Where `X.X.X` is the [latest version](https://github.com/github/github_gitbusbusbus_extensions/pkgs/rubygems/github_bus_extensions) of this Gem. You can view a more detailed example [here](stuff)
      ### Publisher
      To construct a publisher, we can first wire up a class that creates a Hydro Bus with a configured publisher. In this example, the publisher will just place a single order for a pizza and place that order onto a Busbus topic called `\"busbus.pizza_project.v1.PizzaOrders\"`. This order (Bus event) will be a hash of data that our consumer will read to learn what details the pizza order that was placed will contain.
    CONTENTS

    issue = create(:issue, repository: repo)

    ref = repo.heads.create("topictoo", repo.heads.find("master").target, repo.owner)
    commit = ref.append_commit({ message: "Add testing_file.md", committer: repo.owner }, repo.owner) do |files|
      files.add("testing_file.md", content)
    end

    pull = PullRequest.create_for(
      repo,
      base: "master",
      head: ref.name,
      user: @user,
      issue: issue,
    )

    review = pull.reviews.create!(
      user: @user,
      head_sha: pull.head_sha,
    )

    orchestrator, _ = execute_orchestrator!(
      body: "test comment",
      diff_base_commit_oid: pull.merge_base,
      diff_end_commit_oid: pull.head_sha,
      diff_start_commit_oid: pull.base_sha,
      line: 4,
      path: "testing_file.md",
      pull_request: pull,
      repository: repo,
      review: review,
    )


    assert_predicate orchestrator.thread, :persisted?
    assert_predicate orchestrator.comment, :persisted?

    assert_equal :succeeded, orchestrator.state.to_sym
  end

  test "persists the correct relations for the newly created thread" do
    repo = create(:repository, owner: @user, from_example: :simple)

    content = <<-CONTENTS
      Simple content to test that the orchestration and our test setup is behaving correctly
      and persisting the correct primary key relations
    CONTENTS

    issue = create(:issue, repository: repo)

    ref = repo.heads.create("topic_for_thread", repo.heads.find("master").target, repo.owner)
    commit = ref.append_commit({ message: "Add testing_file.md", committer: repo.owner }, repo.owner) do |files|
      files.add("testing_file.md", content)
    end

    pull = PullRequest.create_for(
      repo,
      base: "master",
      head: ref.name,
      user: @user,
      issue: issue,
    )

    review = pull.reviews.create!(
      user: @user,
      head_sha: pull.head_sha,
    )

    orchestrator, _ = execute_orchestrator!(
      diff_base_commit_oid: pull.merge_base,
      diff_end_commit_oid: pull.head_sha,
      diff_start_commit_oid: pull.base_sha,
      path: "testing_file.md",
      pull_request: pull,
      repository: repo,
      review: review,
      stop_after_step: :persist_thread
    )

    thread = orchestrator.thread

    assert_equal thread.pull_request_review_id, review.id
    assert_equal thread.pull_request_id, pull.id
    assert_equal thread.repository_id, repo.id
  end

  test "skips orchestration execution and adds errors when validate_end_position_data_in_comparison_for_thread fails" do
    # attempting to explicitly break the check of the same name in
    # the validate_end_position_data_in_comparison_for_thread step
    # to force the orchestration to end and skip
    GitRPC::Util.expects(:valid_full_sha1?).times(5).returns(false)

    orchestrator, _ = execute_orchestrator!(stop_after_step: :validate_end_position_data_in_comparison_for_thread)
    thread = orchestrator.thread

    assert_equal :skipped, orchestrator.state.to_sym
    assert_equal orchestrator.error_message, "Failed to create comment: #{thread.errors.full_messages}."
    assert_equal :validate_end_position_data_in_comparison_for_thread, orchestrator.step_name&.to_sym
  end

  # ------------------------------------------------------------
  #### Comment tests
  # ------------------------------------------------------------

  test "does not persist a comment if the body is blank" do
    assert_no_difference -> { PullRequestReviewComment.count }  do
      orchestrator, _ = execute_orchestrator!(body: "")

      assert_equal :skipped, orchestrator.state.to_sym
      assert_equal orchestrator.error_message, "Failed to create comment: #{orchestrator.comment.errors.full_messages}."
      assert_equal :validate_attributes_for_comment, orchestrator.step_name&.to_sym
    end
  end

  test "touches a pull request when the comment is a legacy comment" do
    PullRequestReviewComment.any_instance.expects(:legacy_comment?).once.returns(true)
    @pull.expects(:touch).once

    orchestrator, _ = execute_orchestrator!(stop_after_step: :touch_pull_request_after_commit_for_comment)
    comment = orchestrator.comment

    assert_predicate comment, :persisted?
  end

  test "does not touch a pull request when the comment is a legacy comment" do
    PullRequestReviewComment.any_instance.expects(:legacy_comment?).once.returns(false)
    @pull.expects(:touch).never

    orchestrator, _ = execute_orchestrator!(stop_after_step: :touch_pull_request_after_commit_for_comment)
    comment = orchestrator.comment

    assert_predicate comment, :persisted?
  end

  test "instruments the creation of the new comment" do
    GlobalInstrumenter.stubs(:instrument)

    PullRequestReviewComment.any_instance.expects(:instrument).with(
      :create,
    ).once

    GlobalInstrumenter.expects(:instrument).with(
      "pull_request_review_comment.create",
      has_entries(
        actor: @user,
        pull_request: @pull,
        issue: @pull.issue,
        pull_request_creator: @pull.user,
        repository: @repo,
        repository_owner: @user,
        pull_request_review: @review,
      )
    ).once

    execute_orchestrator!(stop_after_step: :instrument_creation_for_comment)
  end

  test "calls subscribe_and_notify for the comment if the comment is not importing" do
    PullRequestReviewComment.any_instance.expects(:importing?).times(4).returns(false)
    PullRequestReviewComment.any_instance.expects(:subscribe_and_notify).once

    execute_orchestrator!(stop_after_step: :subscribe_and_notify_for_comment)
  end

  test "does not call subscribe_and_notify if the comment is not importing" do
    PullRequestReviewComment.any_instance.expects(:importing?).times(4).returns(true)
    PullRequestReviewComment.any_instance.expects(:subscribe_and_notify).never

    execute_orchestrator!(stop_after_step: :subscribe_and_notify_for_comment)
  end

  test "triggers platform subscriptions for the comment" do
    PullRequestReviewComment.any_instance.expects(:trigger_platform_subscriptions).once

    execute_orchestrator!(stop_after_step: :trigger_platform_subscriptions_for_comment)
  end

  test "subscribes to the issue for the comment" do
    PullRequestReviewComment.any_instance.expects(:subscribe_to_issue).once

    execute_orchestrator!(stop_after_step: :subscribe_to_issue_for_comment)
  end

  test "persists the correct relations for the newly created comment" do
    repo = create(:repository, owner: @user, from_example: :simple)

    content = <<-CONTENTS
      Simple content to test that the orchestration and our test setup is behaving correctly
      and persisting the correct primary key relations. Lorem ipsum for sake of file length
      and inclusion of line number in params below:

      Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc sed sem congue, malesuada
      dui ac, pretium ipsum. Vestibulum a leo sed mauris feugiat euismod in id felis. Mauris
      erat enim, ultricies vitae odio ut, tristique porta mi. Donec consectetur vel tortor eu
      gravida. Nullam molestie placerat velit, non sodales leo laoreet at. Vestibulum vel
      maximus lacus, mollis vulputate eros. Etiam quam metus, euismod sit amet auctor ac,
      convallis eget urna. Pellentesque pellentesque imperdiet aliquet. Sed eget ligula nec
      augue aliquam cursus. Sed finibus rhoncus massa vestibulum tristique. Nulla facilisi.
      Vestibulum dapibus fringilla volutpat. Phasellus facilisis augue eget eros sagittis
      ultricies. Orci varius natoque penatibus et magnis dis parturient montes, nascetur
      ridiculus mus.
    CONTENTS

    issue = create(:issue, repository: repo)

    ref = repo.heads.create("topic_for_comment", repo.heads.find("master").target, repo.owner)
    commit = ref.append_commit({ message: "Add testing_file.md", committer: repo.owner }, repo.owner) do |files|
      files.add("testing_file.md", content)
    end

    pull = PullRequest.create_for(
      repo,
      base: "master",
      head: ref.name,
      user: @user,
      issue: issue,
    )

    review = pull.reviews.create!(
      user: @user,
      head_sha: pull.head_sha,
    )

    orchestrator, _ = execute_orchestrator!(
      body: "test comment",
      diff_base_commit_oid: pull.merge_base,
      diff_end_commit_oid: pull.head_sha,
      diff_start_commit_oid: pull.base_sha,
      line: 4,
      path: "testing_file.md",
      pull_request: pull,
      repository: repo,
      review: review,
      stop_after_step: :persist_comment
    )

    comment = orchestrator.comment
    thread = orchestrator.thread

    assert_equal comment.pull_request_review_thread_id, thread.id
    assert_equal comment.pull_request_review_id, review.id
    assert_equal comment.pull_request_id, pull.id
    assert_equal comment.repository_id, repo.id
  end

  test "instruments failed validation for the comment if the comment fails validation" do
    PullRequestReviewComment.any_instance.expects(:body).times(2).returns(nil)
    PullRequestReviewComment.any_instance.expects(:instrument).with(:validation_failed).once

    orchestrator, _ = execute_orchestrator!(submit_review: true, stop_after_step: :validate_attributes_for_comment)

    assert_equal :skipped, orchestrator.state.to_sym
  end

  test "validates body attribute for the comment" do
    PullRequestReviewComment.any_instance.expects(:body).times(3).returns(nil)

    orchestrator, _ = execute_orchestrator!(submit_review: true, stop_after_step: :validate_attributes_for_comment)
    comment = orchestrator.comment

    assert_equal :skipped, orchestrator.state.to_sym
    assert_equal :validate_attributes_for_comment, orchestrator.step_name&.to_sym
    assert_equal comment.errors.full_messages.first, "Body can't be blank"
    assert_equal orchestrator.error_message, "Failed to create comment: #{comment.errors.full_messages}."
  end

  test "validates state attribute for the comment" do
    PullRequestReviewComment.any_instance.expects(:state).once.returns(nil)

    orchestrator, _ = execute_orchestrator!(submit_review: true, stop_after_step: :validate_attributes_for_comment)
    comment = orchestrator.comment

    assert_equal :skipped, orchestrator.state.to_sym
    assert_equal :validate_attributes_for_comment, orchestrator.step_name&.to_sym
    assert_equal comment.errors.full_messages.first, "State does not exist"
    assert_equal orchestrator.error_message, "Failed to create comment: #{comment.errors.full_messages}."
  end

  test "validates bytesize of body attribute for the comment" do
    PullRequestReviewComment.any_instance.expects(:body).times(4).returns("a" * (MYSQL_UNICODE_BLOB_LIMIT + 1))

    orchestrator, _ = execute_orchestrator!(submit_review: true, stop_after_step: :validate_attributes_for_comment)
    comment = orchestrator.comment

    assert_equal :skipped, orchestrator.state.to_sym
    assert_equal :validate_attributes_for_comment, orchestrator.step_name&.to_sym
    assert_equal comment.errors.full_messages.first, "Body bytesize is larger than MYSQL unicode blob limit"
    assert_equal orchestrator.error_message, "Failed to create comment: #{comment.errors.full_messages}."
  end

  test "fails if user_can_interact adds errors to the comment" do
    @disallowed_user = create(:user, login: "disallowedUser")

    GitHub.stubs(interaction_limits_enabled?: true)
    User::InteractionAbility.toggle_interaction_ban(@disallowed_user)

    orchestrator, _ = execute_orchestrator!(author: @disallowed_user, stop_after_step: :validate_user_can_interact_for_comment)
    comment = orchestrator.comment

    assert_equal :failed, orchestrator.state.to_sym
    assert_equal :validate_user_can_interact_for_comment, orchestrator.step_name&.to_sym
    assert_equal comment.errors.full_messages.first, "ability has been suspended for 1 day. If you believe this is in error, please contact GitHub support"
    assert_equal orchestrator.error_message, "Failed to create comment: #{comment.errors.full_messages}."
  end

  test "skips execution if the comment's issue is locked and the commenting user cannot push to the repo" do
    Issue.any_instance.expects(:locked?).once.returns(true)
    Repository.any_instance.expects(:pushable_by?).with(@user).once.returns(false)

    orchestrator, _ = execute_orchestrator!(stop_after_step: :validate_orchestration_can_proceed)

    assert_equal :skipped, orchestrator.state.to_sym
    assert_equal :validate_orchestration_can_proceed, orchestrator.step_name&.to_sym
    assert_equal orchestrator.error_message, "Failed to create comment: Lock prevents comment"
  end

  test "succeeds if the comment's issue is locked but the commenting user can push to the repo" do
    Issue.any_instance.expects(:locked?).once.returns(true)
    Repository.any_instance.expects(:pushable_by?).with(@user).once.returns(true)

    execute_orchestrator!(stop_after_step: :validate_orchestration_can_proceed)
  end

  test "fails if the user is not authorized to create content for the comment" do
    auth_obj = ("ContentAuthorizer::RepoAuthorizer").constantize
    ContentAuthorizer.stubs(:authorize).returns(auth_obj)
    auth_obj.stubs(:failed?).returns(true)
    auth_obj.stubs(:error_messages).returns("User unauthorized")

    orchestrator, exception = execute_orchestrator!(stop_after_step: :validate_creator_is_authorized_to_comment)
    comment = orchestrator.comment

    assert_nil exception
    assert_equal :failed, orchestrator.state.to_sym
    assert_equal :validate_creator_is_authorized_to_comment, orchestrator.step_name&.to_sym
    assert_equal comment.errors.full_messages.first, "User unauthorized"
    assert_equal orchestrator.error_message, "Failed to create comment: User unauthorized."
  end

  test "fails if the comment's user is blocked from reviewing the pull request" do
    @pull.expects(:blocked_from_reviewing?).with(@user).once.returns(true)

    orchestrator, exception = execute_orchestrator!(stop_after_step: :validate_creator_is_authorized_to_comment)

    assert_nil exception
    assert_equal :failed, orchestrator.state.to_sym
    assert_equal :validate_creator_is_authorized_to_comment, orchestrator.step_name&.to_sym
    assert_equal orchestrator.error_message, "Failed to create comment: User is blocked"
  end

  test "skips execution if the comment does not have a review before persistence" do
    @review.expects(:pending?).once.returns(false)

    orchestrator, _ = execute_orchestrator!(stop_after_step: :validate_orchestration_can_proceed)

    assert_equal :skipped, orchestrator.state.to_sym
    assert_equal :validate_orchestration_can_proceed, orchestrator.step_name&.to_sym
    assert_equal orchestrator.error_message, "Failed to create comment: Pull request review must be pending"
  end

  # ------------------------------------------------------------
  #### Review tests
  # ------------------------------------------------------------

  test "comments on the review if submit_review is true" do
    now = Time.zone.now.round

    Timecop.freeze(now) do
      orchestrator, _ = execute_orchestrator!(submit_review: true, stop_after_step: :comment_review)
      comment = orchestrator.comment

      assert comment
      assert_equal now, comment.created_at
      assert_equal now, @review.submitted_at
      assert_predicate @review, :commented?
    end
  end

  test "does not comment on the review if submit_review is false" do
    orchestrator, _ = execute_orchestrator!(stop_after_step: :comment_review)
    comment = orchestrator.comment

    assert_nil @review.submitted_at
    assert_predicate @review, :pending?
    assert_predicate comment, :pending?
  end

  test "validates the review has a body and comments if submit_review is true" do
    # this feels like a contrived test and check in the context of the
    # orchestration since it is responsible for creating a comment
    # specifically attached to the orchestration's review

    @review.update(body: nil)
    @review.review_comments.each { |c| c.delete }

    orchestrator, exception = execute_orchestrator!(submit_review: true)
    review = orchestrator.public_review

    assert_nil exception
    assert_equal :failed, orchestrator.state.to_sym
    assert_equal :validate_body_and_comments_for_review, orchestrator.step_name&.to_sym
    assert_equal orchestrator.error_message, "Failed to create comment: #{review.errors.full_messages}."
  end

  test "submits the review's comments if submit_review is true" do
    orchestrator, _ = execute_orchestrator!(
      submit_review: true,
      stop_after_step: :submit_review
    )

    comment = orchestrator.comment

    assert comment
    assert_predicate comment.reload, :submitted?
  end

  test "does not submit the review's comments or transition the review if submit_review is false" do
    orchestrator, _ = execute_orchestrator!(
      submit_review: false,
    )

    comment = orchestrator.comment
    review = orchestrator.public_review

    assert review
    assert comment
    assert_predicate comment, :pending?
    assert_predicate review, :pending?
  end

  test "fulfills a review if submit_review is true and the review satisfies a review request" do
    org = create(:organization, admin: @user)
    org.allow_private_repository_forking(actor: @user)
    @repo.update(owner: org)
    @repo.add_member @forker, action: :write

    review_request = @pull.review_requests.create!(reviewer: @user, deferred: true)

    assert_predicate review_request, :deferred

    orchestrator, _ = execute_orchestrator!(
      submit_review: true,
      stop_after_step: :fulfill_review,
    )

    review = orchestrator.public_review
    review_request_from_orch = review.review_requests.first
    refute_predicate T.must(review_request_from_orch).reload, :deferred
  end

  test "does not fulfill a review if submit_review is false" do
    org = create(:organization, admin: @user)
    org.allow_private_repository_forking(actor: @user)
    @repo.update(owner: org)
    @repo.add_member @forker, action: :write

    review_request = @pull.review_requests.create!(reviewer: @user, deferred: true)

    assert_predicate review_request, :deferred

    orchestrator, _ = execute_orchestrator!(
      submit_review: false,
      stop_after_step: :fulfill_review,
    )

    review_request_from_orch = @pull.review_requests_for(orchestrator.public_review.user).first
    assert_predicate review_request_from_orch.reload, :deferred
  end

  test "increments the pull request's comment counters if submit_review is true" do
    assert_changes -> { @pull.reload.review_comments_with_body_count }, from: nil, to: 1 do
      orchestrator, _ = execute_orchestrator!(submit_review: true, stop_after_step: :update_pull_request_counters_for_review)
    end
  end

  test "changes the pull request's comment from nil to zero if submit_review is false" do
    assert_changes -> { @pull.reload.review_comments_with_body_count }, from: nil, to: 0 do
      orchestrator, _ = execute_orchestrator!(submit_review: false, stop_after_step: :update_pull_request_counters_for_review)
    end
  end

  test "instruments a review via the after_commit_review step if submit_review is true"  do
    GlobalInstrumenter.stubs(:instrument)
    GlobalInstrumenter.expects(:instrument).with(
      "pull_request_review_comment.create",
      has_entries(
        actor: @user,
        pull_request: @pull,
        issue: @pull.issue,
        pull_request_creator: @pull.user,
        repository: @repo,
        repository_owner: @user,
        pull_request_review: @review,
      )
    )

    @review.expects(:instrument).with(
      :submit,
      has_entries(
        id: @review.id,
        state: 1,
        issue_id: @pull.issue&.id,
        actor: @review.user,
        pull_request_author: @pull.user,
        new_reviewer_was_added: @review.new_reviewer_added?,
      )
    ).once

    GlobalInstrumenter.expects(:instrument).with(
      "pull_request_review.submit",
      has_entries(
        review: @review,
        importing: @review.importing?
      )
    )

    Events::PullRequestReviewPublisher.expects(:submitted).with(@review).once

    @review.expects(:subscribe_and_notify).once
    @pull.expects(:notify_socket_subscribers).once
    @pull.expects(:synchronize_search_index).once

    execute_orchestrator!(submit_review: true)
  end

  # ------------------------------------------------------------
  #### Tests replicated from ReviewThreadCreatorTest
  # ------------------------------------------------------------

  test "creates a comment on a deletion" do
    orchestrator, _ = execute_orchestrator!(
      side: :left,
      line: 18
    )

    thread = orchestrator.thread
    comment = orchestrator.comment

    assert_predicate thread, :persisted?
    assert_predicate comment, :persisted?
    assert_predicate thread, :left_blob?
  end

  test "fails, creates no comment, and returns thread with errors for bad data" do
    orchestrator, _ = execute_orchestrator!(line: 100)

    thread = orchestrator.thread
    comment = orchestrator.comment

    assert_equal :skipped, orchestrator.state.to_sym
    assert_equal orchestrator.error_message, "Failed to create comment: #{thread.errors.full_messages}."
    assert_equal :validate_end_position_data_for_line_level_thread, orchestrator.step_name&.to_sym

    refute_predicate thread, :persisted?
    refute_predicate comment, :persisted?
    assert_includes thread.errors.full_messages, "Line must be part of the diff"
  end

  test "creates a thread when supplied with an file subject type" do
    orchestrator, _ = execute_orchestrator!(subject_type: :file)

    thread = orchestrator.thread
    comment = orchestrator.comment

    assert_predicate thread, :persisted?
    assert_predicate comment, :persisted?
    assert_equal thread.subject_type, "file"
  end

  test "create orchestration creates a new comment with Japanese characters and instruments an update when submitted as solo comment" do
    PullRequestReviewComment.any_instance.expects(:instrument).with(
      :create,
    ).once

    PullRequestReviewComment.any_instance.expects(:instrument).with(
      :submission,
    ).once

    PullRequestReviewComment.any_instance.expects(:instrument).with(
      :update,
    ).never

    orchestrator, _ = execute_orchestrator!(
      path: "aquaman.txt",
      body: "レビューコメント - 日本語",
      line: 24,
      submit_review: true,
    )

    comment = orchestrator.comment
    thread = orchestrator.thread

    assert_predicate thread, :persisted?
    assert_predicate comment, :persisted?

    assert_equal :succeeded, orchestrator.state.to_sym
    assert_equal "レビューコメント - 日本語", comment.body
    assert_equal "aquaman.txt", thread.path
    assert_equal 24, thread.line
  end

  test "creates a thread when supplied with an file subject type and a nil line parameter" do
    orchestrator, _ = execute_orchestrator!(
      author: @user,
      path: "aquaman.txt",
      body: "new comment",
      pull_request: @pull,
      line: nil,
      side: :left,
      submit_review: false,
      subject_type: :file,
      repository: @repo,
      review: @review,
      diff_start_commit_oid: @pull.base_sha,
      diff_end_commit_oid: @pull.head_sha,
      diff_base_commit_oid: @pull.merge_base,
    )

    thread = orchestrator.thread
    comment = orchestrator.comment

    assert_predicate thread, :persisted?
    assert_predicate comment, :persisted?
    assert_equal thread.subject_type, "file"
  end
end

# These tests call share_spokesdb, which disables transactional tests. Calling this slows tests down drastically,
# so isolate the tests which need it to their own class.
class CreateNewPullRequestReviewCommentOrchestrationTestSharedSpokes < CreateNewPullRequestReviewCommentOrchestrationTestBase
  Spokesd.share_spokesdb(self)

  test "marks comments outdated on creation" do
    # TODO: the creation_diff logic is broken and we don't properly mark comments
    # as outdated on creation with this feature flag on so this needs to be
    # revisited if we ever ship comment outside the diff

    GitHub.flipper[:comment_outside_the_diff].disable

    example_repo :review_comment_source, @repo

    base_ref = @repo.heads.find("master")
    head_ref = @repo.heads.create("suggestion-topic", base_ref.target, @repo.owner)

    head_ref.append_commit({
      message: "a change",
      committer: @repo.owner,
    }, @repo.owner) do |files|
      files.add("README.txt", "```\ncode\n```\n")
    end

    pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "suggestion-topic",
      user: @repo.owner,
    )

    sha_before = pull.head_sha

    with_enqueued_pr_sync_jobs do
      head_ref.append_commit({
        message: "a change",
        committer: @repo.owner,
      }, @repo.owner) do |files|
        files.add("README.txt", "```erlang\ncode\n```\n")
      end
    end

    pull.reload

    review = pull.pending_review_for(user: pull.user, head_sha: sha_before)

    orchestrator, _ = execute_orchestrator!(
      author: pull.user,
      path: "README.txt",
      body: "```suggestion\r\n```erlang\r\n```",
      line: 1,
      side: :right,
      submit_review: true,
      review: review,
      pull_request: pull,
      diff_end_commit_oid: sha_before,
      diff_start_commit_oid: pull.base_sha,
      diff_base_commit_oid: pull.base_sha
    )

    thread = orchestrator.thread
    assert thread.outdated
  end
end
