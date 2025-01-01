# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"
require "test_helpers/issue_event_test_helper"
require "test_helpers/query_identifier_helper"

class Issue::CommentLoaderTest < GitHub::TestCase
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

    # adapter
    _, queries = log_cleaned_queries do
      Issue::Loader::CommentLoader.issue_adapter(loader)
    end
    compare_queries "", queries, message: "Expected no queries when creating an IssueAdapter"
  end

  setup do
    Spokesd.enable_spokesd
  end

  test "preloading does not execute unexpected queries" do
    viewer = create(:user)
    repo = create(:repository, owner: viewer)
    issue = create(:issue, repository: repo, user: viewer)

    repo.reload
    assert_queries %{
      #{"businesses" if GitHub.enterprise?}
      close_issue_references
      commit_contributions
      configuration_entries
      issue_reactions
      issue_transfers
      #{ TestEnv.test_all_features? ? "" : "key_links" }
      primary_avatars
      profiles
      repository_unlocks !dotcom
      user_settings
      users
      users
    } do
      Issue::Loader::CommentLoader.new issue, repo, viewer, cap_filter: cap_authorizing_filter
    end
  end

  test "preloading does not execute unexpected queries with a comment" do
    viewer = create(:user)
    repo = create(:repository, owner: viewer)
    issue = create(:issue, repository: repo, user: viewer)
    issue_comment = create(:issue_comment, issue: issue, user: viewer)

    repo.reload

    # reread the issue comment to not have body_html populated by the create hook
    issue_comment = IssueComment.find_by(id: issue_comment.id)
    assert_queries %{
      business_user_accounts
      #{"businesses" if GitHub.enterprise?}
      close_issue_references
      commit_contributions
      configuration_entries
      #{"configuration_entries" unless GitHub.enterprise?}
      issue_comment_edits
      issue_comment_reactions
      issue_reactions
      issue_transfers
      issues
      #{ TestEnv.test_all_features? ? "" : "key_links" }
      #{ TestEnv.test_all_features? ? "" : "key_links" }
      primary_avatars
      profiles
      repositories (We are querying for the repository that the comment is in here)
      repositories
      repositories
      repository_networks
      user_settings
      users
      users
      users
      #{"users" unless GitHub.enterprise?}
      users
    } do
      Issue::Loader::CommentLoader.new issue, repo, viewer, comment: issue_comment, cap_filter: cap_authorizing_filter
    end
  end

  test "preloading does not execute unexpected queries with many comments" do
    viewer = create(:user)
    repo = create(:repository, owner: viewer)
    issue = create(:issue, repository: repo, user: viewer)
    # repository_networks is not loaded
    last_comment = T.let(nil, T.nilable(IssueComment))
    5.times do
      last_comment = create(:issue_comment, issue: issue, user: viewer)
    end
    # reread the issue comment to not have body_html populated by the create hook
    last_comment = IssueComment.find_by(id: T.must(last_comment).id)

    repo.reload

    assert_queries %{
      business_user_accounts
      #{"businesses" if GitHub.enterprise?}
      close_issue_references
      commit_contributions
      configuration_entries
      #{"configuration_entries" unless GitHub.enterprise?}
      issue_comment_edits
      issue_comment_reactions
      issue_reactions
      issue_transfers
      issues
      #{ TestEnv.test_all_features? ? "" : "key_links" }
      #{ TestEnv.test_all_features? ? "" : "key_links" }
      primary_avatars
      profiles
      repositories (We are querying for the repository that the comment is in here)
      repositories
      repositories
      repository_networks
      user_settings
      users
      users
      users
      #{"users" unless GitHub.enterprise?}
      users
    } do
      Issue::Loader::CommentLoader.new issue, repo, viewer, comment: last_comment, cap_filter: cap_authorizing_filter
    end
  end
end
