# frozen_string_literal: true

require "github_helpers"

class CreateReaction
  GRAPHQL_REACTION_MAP = {
    "confused" => "CONFUSED",
    "eyes" => "EYES",
    "heart" => "HEART",
    "hooray" => "HOORAY",
    "laugh" => "LAUGH",
    "rocket" => "ROCKET",
    "-1" => "THUMBS_DOWN",
    "+1" => "THUMBS_UP",
  }.freeze

  def initialize(reaction:, comment_id:, comment_type:,
                 issue: nil, pull_request: nil)
    @reaction = reaction
    @comment_id = comment_id
    @comment_type = comment_type
    @issue_or_pr = issue || pull_request

    raise unless issue_or_pr
  end

  def run
    create_reaction_if_possible
  rescue Octokit::Unauthorized
    retrying ||= false
    raise if retrying

    retrying = true
    uncache_installation_client
    retry
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: issue_or_pr.repo,
      event_source: "action.create_reaction",
    ).run
  end

  private

  attr_reader :issue_or_pr, :reaction, :comment_id, :comment_type

  def create_reaction_if_possible
    case comment_type.to_sym
    when :review then create_review_reaction
    when :review_comment then create_review_comment_reaction
    when :issue_comment then create_issue_comment_reaction
    else raise "Unexpected comment type: #{comment_type}"
    end
  rescue Octokit::Forbidden => e
    raise unless e.message.include?("issue is locked")
  end

  def create_review_reaction
    GitHubGraphQL.client.query(
      graphql_reaction_mutation,
      variables: {
        id: comment_id,
        reaction: GRAPHQL_REACTION_MAP.fetch(reaction),
      },
      context: {
        account: issue_or_pr.repo.account,
      },
    )
  end

  def create_review_comment_reaction
    installation_github_client.create_pull_request_review_comment_reaction(
      issue_or_pr.repo.github_id,
      comment_id,
      reaction,
    )
  end

  def create_issue_comment_reaction
    installation_github_client.create_issue_comment_reaction(
      issue_or_pr.repo.github_id,
      comment_id,
      reaction,
    )
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(account: issue_or_pr.repo.account)
  end

  def uncache_installation_client
    GitHubHelpers.delete_cached_access_token_for(
      account: issue_or_pr.repo.account,
    )
    @installation_github_client = nil
  end

  def graphql_reaction_mutation
    GitHubGraphQL.client.parse <<-'GRAPHQL'
      mutation($id: ID!, $reaction: ReactionContent!) {
        addReaction(input: { subjectId: $id, content: $reaction }) {
          reaction {
            content
          }
          subject {
            id
          }
        }
      }
    GRAPHQL
  end
end
