# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::LinkableSearchController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Collab,
  ApplicationRecord::Configurations,
  ApplicationRecord::Repositories,
  ApplicationRecord::IssuesPullRequests,
  ApplicationRecord::IamAbilities,
  only: [:index]


  before_action :login_required
  before_action :privacy_check

  PRS_LIMIT = 10
  BRANCHES_LIMIT = 10
  PULL_REQUESTS_SORT_ORDER = "updated-desc"

  sig { returns(T.untyped) }
  def index
    respond_to do |format|
      format.json do
        pull_requests = pull_requests_filtered(query_value.strip)
        pr_results = pull_requests.map do |pr|
          {
            type: "pull_request",
            title: pr["title"],
            number: pr["number"],
            state: refine_pr_state(pr["state"].upcase, pr["draft"], pr["merged"]),
          }
        end

        skip_branch_names = pull_requests.map { |pr| pr["head_ref"] }.map(&:downcase).to_set
        skip_branch_names << current_repository.default_branch.downcase

        branches = branches_filtered(query_value, skip_branch_names)
        branch_results = branches.map do |branch|
          {
            type: "branch",
            name: branch.name,
          }
        end

        render json: { results: pr_results + branch_results }, status: :ok
      end
    end
  end

  private

  sig { params(state: String, draft: T::Boolean, merged: T::Boolean).returns(String) }
  def refine_pr_state(state, draft, merged)
    state_up = state.upcase
    case state_up
    when "CLOSED"
      merged ? "MERGED" : "CLOSED"
    when "OPEN"
      draft ? "DRAFT" : "OPEN"
    else
      state_up
    end
  end

  sig { returns(String) }
  def query_value
    params[:query].to_s
  end

  sig { params(query_value: String).returns(T::Array[T::Hash[String, T.untyped]]) }
  def pull_requests_filtered(query_value)
    phrase = "sort:#{PULL_REQUESTS_SORT_ORDER}"
    if query_value.present?
      phrase += " #{query_value}"
    end
    response = Search::Queries::IssueQuery.new(
      type: "pr",
      phrase: phrase,
      repo_id: current_repository.id,
      source_fields: %w[title number head_ref merged draft state],
      per_page: PRS_LIMIT,
    ).execute
    response.results.each_with_object([]) do |result, pull_requests|
      pull_requests << result["_source"]
    end
  end

  sig { params(query_value: String, skip_branch_names: T::Set[String]).returns(T::Array[T.untyped]) }
  def branches_filtered(query_value, skip_branch_names)
    current_repository.heads
      .substring_filter(substring: query_value.downcase, limit: BRANCHES_LIMIT, case_sensitive: false)
      .reject { |b| skip_branch_names.include?(b.name.downcase) }
  end
end
