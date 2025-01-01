# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/pull_requests"

require "test_helpers/commit_tree_helper"


class PullRequestReviewThreadOutsideDiffTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers
  include PullRequestIntegrationTestHelpers
  include PlatformTestHelpers::InterfaceHelpers

  RANGE_END = "c4465f65f93774e1780f9979cbbd63294a0ba7b0"

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :pull_request_source)


    master = @repo.heads.find_or_build("master")
    quotes = <<~EOF
    Okay, back to Winnipeg!
    I said french fries!
    Batman's a scientist!

    Sir, I need to know where I can get some business hammocks.

    There ain't no monorail here and there never was.

    Not in Utica, no. It's an Albany expression.

    Ketchup... Catsup.

    You better believe that's a paddlin.

    This sidewalk's for regular walking. Not fancy walking.

    People should only be let out of jail on technicalities.

    You should have thought of that before you gave me the old "sugar me do"
    EOF
    master.append_commit({ message: "initial file commit", committer: @user }, @user) do |files|
      files.add("quotes.txt", quotes)
    end

    ref = @repo.heads.create("topic", master.target_oid, @user)

    modified_quotes = <<~EOF
    Okay, back to Winnipeg!

    I said french fries!

    Batman's a scientist!

    Sir, I need to know where I can get some business hammocks.

    There ain't no monorail here and there never was.

    Not in Utica, no. It's an Albany expression.

    Ketchup... Catsup.

    You better believe that's a paddlin.

    This sidewalk's for regular walking. Not fancy walking.

    People should only be let out of jail on technicalities.

    You should have thought of that before you gave me the old "sugar me do"
    EOF

    ref.append_commit({ message: "moar quotes", committer: @user }, @user) do |files|
      files.add("quotes.txt", modified_quotes)
    end

    @pull = create(:pull_request, repository: @repo, base_repository: @repo, head_repository: @repo, head_ref: "topic")

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  def create_review_thread
    args = {
      author: @user,
      review: @pull.pending_review_for(user: @user),
      body: "regular comment",
      path: "quotes.txt",
      line: 18
    }
    thread, _ = ReviewThreadCreator.new(**args).create_thread
    thread
  end

  test "outside-the-diff comment doesn't become outdated by a push that changes another line but keeps position the same" do
    GitHub.flipper[:comment_outside_the_diff].enable(@repo)

    thread = create_review_thread

    # first line is modified
    quotes_txt_updated = <<~EOF
    Okay! back to Winnipeg!

    I said french fries!

    Batman's a scientist!

    Sir, I need to know where I can get some business hammocks.

    There ain't no monorail here and there never was.

    Not in Utica, no. It's an Albany expression.

    Ketchup... Catsup.

    You better believe that's a paddlin.

    This sidewalk's for regular walking. Not fancy walking.

    People should only be let out of jail on technicalities.

    You should have thought of that before you gave me the old "sugar me do"
    EOF

    commit = @repo.commits.create({ message: "modifying first line of quotes", committer: @user }, @pull.head_sha) do |files|
      files.add("quotes.txt", quotes_txt_updated)
    end

    only = [PullRequestSynchronizationJob, SynchronizePullRequestJob]
    perform_enqueued_jobs(only: only) { @repo.heads.find(@pull.head_ref).update(commit, @user) }
    @pull.reload
    thread.reload

    refute_predicate thread, :outdated?
  end

  test "outside-the-diff comment doesn't become outdated by a push that shifts position down some" do
    GitHub.flipper[:comment_outside_the_diff].enable(@repo)
    thread = create_review_thread

    quotes_txt_updated = <<~EOF
    Okay! back to Winnipeg!

    The fumes are making me dizzy! Yeah, they'll do that.

    I'm seeing double! Four Krustys!

    I said french fries!

    Batman's a scientist!

    Sir, I need to know where I can get some business hammocks.

    There ain't no monorail here and there never was.

    Not in Utica, no. It's an Albany expression.

    Ketchup... Catsup.

    You better believe that's a paddlin.

    This sidewalk's for regular walking. Not fancy walking.

    People should only be let out of jail on technicalities.

    You should have thought of that before you gave me the old "sugar me do"
    EOF

    commit = @repo.commits.create({ message: "modifying first line of quotes", committer: @user }, @pull.head_sha) do |files|
      files.add("quotes.txt", quotes_txt_updated)
    end

    only = [PullRequestSynchronizationJob, SynchronizePullRequestJob]
    perform_enqueued_jobs(only: only) { @repo.heads.find(@pull.head_ref).update(commit, @user) }
    @pull.reload
    thread.reload

    refute_predicate thread, :outdated?
  end

  test "multi-line outside-the-diff comment doesn't become outdated by a push" do
    GitHub.flipper[:comment_outside_the_diff].enable(@repo)
    thread = create_review_thread

    refute_predicate thread, :outdated?

    # first line is modified
    quotes_txt_updated = <<~EOF
    Okay! back to Winnipeg!

    I said french fries!

    Batman's a scientist!

    Sir, I need to know where I can get some business hammocks.

    There ain't no monorail here and there never was.

    Not in Utica, no. It's an Albany expression.

    Ketchup... Catsup.

    You better believe that's a paddlin.

    This sidewalk's for regular walking. Not fancy walking.

    People should only be let out of jail on technicalities.

    You should have thought of that before you gave me the old "sugar me do"
    EOF

    commit = @repo.commits.create({ message: "modifying first line of quotes", committer: @user }, @pull.head_sha) do |files|
      files.add("quotes.txt", quotes_txt_updated)
    end

    only = [PullRequestSynchronizationJob, SynchronizePullRequestJob]
    perform_enqueued_jobs(only: only) { @repo.heads.find(@pull.head_ref).update(commit, @user) }
    @pull.reload
    thread.reload

    refute_predicate thread, :outdated?
  end
end
