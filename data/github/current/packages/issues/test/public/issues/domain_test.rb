# typed: true
# frozen_string_literal: true

require "test_helper"

class Issues::Domain::IssueTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers
  include ResiliencyHelpers

  def initialize(*args)
    @domain = T.let(Issues::Domain.new, Issues::Domain)
    super
  end

  fixtures do
    @user = create(:user)
    @other_user = create(:user)
    @repo = create(:repository, owner: @user)
    @issue = create(:issue, repository: @repo)
    @other_issue = create(:issue)
  end

  setup do
    @domain = Issues::Domain.new
  end

  context "#by_number" do
    test "finds issues by their number" do
      assert_no_query_warnings do
        assert_equal @issue, @domain.by_number(@issue.number, repo_id: @repo.id)
      end
    end

    test "returns nil for non-existent issue" do
      assert_nil @domain.by_number(-2, repo_id: @repo.id)
    end
  end

  context "#open_issue_and_pr_counts" do
    test "returns counts of open issues and prs from a list of repository ids" do
      2.times { create(:issue, repository: @repo) }
      create(:issue, repository: @repo, state: :closed)
      create(:pull_request, :disable_disk_access, repository: @repo, user: @user)

      counts = T.must(Issues::Domain.new.open_issue_and_pr_counts(repository_ids: [@repo.id]))

      assert_equal 3, counts[[@repo.id, false]]
      assert_equal 1, counts[[@repo.id, true]]
    end

    if GitHub.spamminess_check_enabled?
      test "returns counts for non spammy open issues and prs from a list of repository ids" do
        repo = create(:repository, name: "simple",  owner: @user)
        spammy_user = create(:user, login: "spammy")
        create(:issue, user: spammy_user, repository: repo)
        2.times { create(:issue, repository: repo) }
        create(:issue, repository: repo, state: :closed)
        create(:pull_request, :disable_disk_access, repository: repo, user: @user)

        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
          spammy_user.mark_as_spammy hard_flag: true
        end

        counts = T.must(Issues::Domain.new.open_issue_and_pr_counts(repository_ids: [repo.id]))

        assert_equal 2, counts[[repo.id, false]]
        assert_equal 1, counts[[repo.id, true]]
      end
    end

    test "returns nil if database fails and return_nil_on_failure is set to true" do
      repo = create :repository, owner: @user, from_example: :pull_request_source

      create :issue, repository: repo
      create :pull_request, :with_mergeable_head, repository: repo

      db_result = prevent_connections_to(ApplicationRecord::IssuesPullRequests) do
        Issues::Domain.new.open_issue_and_pr_counts(repository_ids: [repo.id], return_nil_on_failure: true)
      end

      assert_nil db_result
    end
  end
end
