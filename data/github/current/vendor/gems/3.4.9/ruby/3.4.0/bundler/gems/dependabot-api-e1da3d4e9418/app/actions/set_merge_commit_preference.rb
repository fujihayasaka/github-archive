# frozen_string_literal: true

class SetMergeCommitPreference
  attr_reader :repo

  class ServerError < StandardError; end

  CommitMessagesQuery = GitHubGraphQL.client.parse <<-'GRAPHQL'
    query($owner_name: String!, $repo_name: String!) {
      repository(owner: $owner_name, name: $repo_name) {
        pullRequests(last: 100, states: [MERGED]) {
          nodes {
            mergedBy {
              login
            }
            mergeCommit {
              message
            }
          }
        }
      }
    }
  GRAPHQL

  def initialize(repo:)
    @repo = repo
  end

  def run
    return unless repo.account.active?
    return if commit_messages.none?

    repo.account.update!(create_merge_commits: create_merge_commits?)
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: repo,
      event_source: "action.set_merge_commit_preference",
    ).run
  end

  private

  def create_merge_commits?
    merges_using_merge_commit.count.to_f / commit_messages.count > 0.5
  end

  def merges_using_merge_commit
    commit_messages.select { |m| m.start_with?("Merge") }
  end

  def commit_messages # rubocop:disable Metrics/PerceivedComplexity
    return @commit_messages if @commit_messages

    response = make_graphql_request

    raise ServerError if response.errors[:data].join(", ").match?(/^5\d\d\s/)
    raise response.errors[:data].join(", ") if response.errors.any?
    return [] unless response.data.repository

    @commit_messages =
      response.data.repository.pull_requests.nodes.
      reject { |n| n.merged_by&.login == integration_name }.
      reject { |n| n.merge_commit.nil? }.
      map { |n| n.merge_commit.message }
  end

  def make_graphql_request
    GitHubGraphQL.client.query(
      CommitMessagesQuery,
      context: {
        account: repo.account,
      },
      variables: {
        owner_name: repo.account.github_login,
        repo_name: repo.name,
      },
    )
  end

  def integration_name
    Prius.get(:github_integration_name)
  end
end
