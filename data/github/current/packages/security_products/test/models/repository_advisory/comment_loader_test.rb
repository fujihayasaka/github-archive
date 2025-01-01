# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"
require "test_helpers/issue_event_test_helper"
require "test_helpers/query_identifier_helper"

class RepositoryAdvisory::CommentLoaderTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include IssueEventTestHelper
  include GitHub::PullRequestTestHelpers
  include QueryIdentifierHelper

  def compare_queries(expected_queries, actual_queries, message: nil)
    assert_equal parse_queries(expected_queries), identify_queries(actual_queries).sort, message
  end

  def assert_queries(expected_queries)
    # loader
    loader, queries = log_cleaned_queries do
      yield
    end
    compare_queries expected_queries, queries, message: "Unexpected queries while loading data"
  end

  def assert_adapters_execute_no_queries(advisory_context, comments)
    _, queries = log_cleaned_queries do
      comments.each do |comment|
        RepositoryAdvisory::Adapter::CommentAdapter.new(advisory_context, comment)
      end
    end

    compare_queries "", queries, message: "Expected no queries when creating an Adapter"
  end

  test "preloading does not execute unexpected queries for an advisory" do
    user = create(:user)
    repo = create(:repository, owner: user)
    advisory = create(:repository_advisory, author: user, repository: repo)

    advisory_context = RepositoryAdvisory::Adapter::Context.new(advisory, repo, user)
    comments = [advisory]

    use_contribution_summaries = GitHub.commit_contribution_summaries_enabled?

    assert_queries %{
      abilities
      abilities
      abilities
      #{use_contribution_summaries ? "commit_contribution_summaries" : "commit_contributions"}
      primary_avatars
      profiles
      reactions
      reactions
      repository_advisory_edits
      repository_unlocks !dotcom
      user_emails !enterprise
      user_emails !enterprise
      users
    } do
      RepositoryAdvisory::Loader::AdvisoryComments.new(advisory_context).preload(comments)
    end

    assert_adapters_execute_no_queries(advisory_context, comments)
  end

  test "preloading does not execute unexpected queries for an advisory with many comments" do
    user = create(:user)
    repo = create(:repository, owner: user)
    advisory = create(:repository_advisory, author: user, repository: repo)

    advisory_context = RepositoryAdvisory::Adapter::Context.new(advisory, repo, user)
    comments = [advisory]

    5.times do
      comments << advisory.comments.create(body: "test", user: advisory.repository.owner)
    end

    use_contribution_summaries = GitHub.commit_contribution_summaries_enabled?

    assert_queries %{
      abilities
      abilities
      abilities
      abilities
      #{use_contribution_summaries ? "commit_contribution_summaries" : "commit_contributions"}
      primary_avatars
      profiles
      reactions
      reactions
      reactions
      reactions
      repository_advisory_edits
      repository_unlocks !dotcom
      user_emails !enterprise
      user_emails !enterprise
      users
    } do
      RepositoryAdvisory::Loader::AdvisoryComments.new(advisory_context).preload(comments)
    end

    assert_adapters_execute_no_queries(advisory_context, comments)
  end
end
