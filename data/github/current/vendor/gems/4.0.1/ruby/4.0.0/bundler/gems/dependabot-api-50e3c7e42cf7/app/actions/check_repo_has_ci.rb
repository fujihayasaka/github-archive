# frozen_string_literal: true

# Checks whether a repo has had any CI runs in recent commits.
# The @dependabot merge comment command uses this data as part
# of some checks to determine whether to fail the command based
# on missing or failed CI runs on a PR.

class CheckRepoHasCi
  CommitStatusCountsQuery = GitHubGraphQL.client.parse <<-'GRAPHQL'
    query($owner_name: String!, $repo_name: String!) {
      repository(owner: $owner_name, name: $repo_name) {
        defaultBranchRef {
          target { ... on Commit {
            history(first: 25) {
              edges {
                node {
                  statusCheckRollup {
                    contexts {
                      totalCount
                    }
                  }
                }
              }
            }
          }}
        }
      }
    }
  GRAPHQL

  def initialize(repo:)
    @repo = repo
  end

  def run
    return unless repo.account.active?

    commit_history = graphql_commit_history

    # If the API call does not return useable data, treat this action as a no-op
    return if commit_history.blank?

    has_ci = ci_on_commits?(commit_history)
    return if repo.has_ci == has_ci

    repo.update!(has_ci: has_ci)
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: repo,
      event_source: "action.check_repo_has_ci",
    ).run
  end

  private

  attr_reader :repo

  def graphql_commit_history
    response = make_graphql_request
    check_response(response)
    if response.data.repository&.default_branch_ref.nil?
      raise Octokit::NotFound if response.original_hash["errors"]&.any?

      return []
    end

    response.data.repository.default_branch_ref.target.history.edges
  end

  def ci_on_commits?(commit_history)
    commit_history.
      filter_map { |e| e.node&.status_check_rollup&.contexts }.
      any? { |context| context.total_count.positive? }
  end

  def make_graphql_request
    GitHubGraphQL.client.query(
      CommitStatusCountsQuery,
      context: {
        account: repo.account,
        accept_header: "application/vnd.github.antiope-preview+json",
      },
      variables: {
        owner_name: repo.account.github_login,
        repo_name: repo.name,
      },
    )
  end

  def check_response(response)
    return if response.errors.none?

    msg = response.errors[:data].join(", ")
    raise GitHubGraphQL::ServerError, msg if msg.match?(/^5\d{2}/)
    raise GitHubGraphQL::UnauthorizedError, msg if msg.start_with?("401 Unauthorize")
    raise GitHubGraphQL::RateLimited, msg if msg.start_with?("403 ")

    raise msg
  end
end
