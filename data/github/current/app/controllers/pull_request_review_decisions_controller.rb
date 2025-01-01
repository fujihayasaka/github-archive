# typed: true
# frozen_string_literal: true
class PullRequestReviewDecisionsController < ApplicationController
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "PullRequestReviewDecisionsController#index",
  ]

  depends_on_clusters(
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false,
    only: [:index],
  )
  # we bypass CAP framework to check permissions, we instead check the permissions explicitly and individually for a batch.
  # we are loading the PRs and their repos, and verifying for each that the user has read access.
  # see https://github.com/github/github/pull/215529/files#r845614700, for context.
  skip_before_action :perform_conditional_access_checks # rubocop:todo GitHub/DoNotSkipCapBeforeAction

  # params[:items] = {
  #   item-0: { pull_request_id: PULL_REQUEST_ID },
  #   item-1: { pull_request_id: PULL_REQUEST_ID },
  #   …
  # }
  def index
    inputs = params.require(:items).permit!.to_h
    keyed_contents = ActiveRecord::Base.connected_to(role: :reading) do
      keyed_objects = load_objects_from_inputs(inputs)
      keyed_objects.each_with_object({}) do |(key, pull_request), contents|
        contents[key] = render_decision(pull_request)
      end
    end

    respond_to do |wants|
      wants.json do
        render json: keyed_contents
      end
    end
  rescue ActionController::ParameterMissing
    head :bad_request
  end

  private

  def load_objects_from_inputs(inputs)
    pr_ids = inputs.values.map { |input| input[:pull_request_id]&.to_i }.compact.uniq
    repo_ids = PullRequest.where(id: pr_ids).pluck(:repository_id)
    repos = Repository.where(id: repo_ids)
    Repository.preload_repository_permissions(users: [current_user], repositories: repos)
    viewable_repos = Promise.all(repos.map { |repo| repo.async_pullable_by?(current_user) }).then do |can_pull|
      filtered_repos = []
      repos.each_with_index do |repo, i|
        filtered_repos << repo if can_pull[i]
      end
      filtered_repos
    end.sync

    prs_by_id = PullRequest.where(id: pr_ids, repository_id: viewable_repos.map(&:id)).index_by(&:id)
    GitHub::PrefillAssociations.prefill_batch_method(prs_by_id.values, :base_branch_rule_evaluator)
    values = inputs.transform_values do |pr_params|
      prs_by_id[pr_params[:pull_request_id]&.to_i]
    end
    values
  end

  def render_decision(pull_request)
    return "" unless pull_request
    render_to_string(
      partial: "pull_requests/pull_request_review_decision",
      formats: [:html],
      locals: { pull_request: pull_request }
    )
  end
end
