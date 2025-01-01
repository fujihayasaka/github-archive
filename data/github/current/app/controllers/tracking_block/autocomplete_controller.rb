# typed: ignore
# frozen_string_literal: true

class TrackingBlock::AutocompleteController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency
  include GitHub::Memoizer

  allow_verified_fetch only: [:show]

  before_action :login_required
  before_action :require_current_issue
  before_action :require_current_block
  before_action :require_tasklist_block

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    only: [:show]

  SEARCH_RESULT_LIMIT = 5

  # Returns Array of autocomplete suggestions for the tracking block omnibar.
  def show
    query = ::Search::Queries::IssueQuery.new(
      current_user: current_user,
      ids_to_exclude: [current_issue.id, *hierarchy_child_ids],
      remote_ip: request.remote_ip,
      repo_id: current_repository.id,
      phrase: munged_phrase,
      source_fields: false,
      per_page: SEARCH_RESULT_LIMIT,
      force_issue_number_terms: true,
      escape_wildcards: false,
      sort: %w[updated desc],
      normalizer: ->(results) { results.filter_map { |r| r["_model"] if valid_hit_type?(r) } },
      context: "#{self.class.name&.demodulize.underscore}-#{__method__}",
    )

    GitHub.dogstats.distribution_time("autocomplete_tracking_block.duration") do
      results = query.execute.results
      # Avoid N+1 while serializing the result. We may need to load pull
      # requests to get PR state.
      GitHub::PrefillAssociations.prefill_associations(results, [:pull_request]) if pr_support_enabled?
      @results = results.map(&:to_omnibar_result)
    end

    query = params.fetch(:q, "").strip

    unless query.start_with?("#", "http")
      @results.prepend({
        id: "add_task",
        title: "Create task called: #{query}",
        state: "new",
        url: query
      })
    end

    respond_to do |format|
      format.html_fragment do
        render "tracking_block/autocomplete",
          formats: :html,
          layout: false,
          locals: {
            hits: @results,
            query: query
          }
      end
    end
  end

  private

  # Private: Escape user input then massage the phrase to be more specific for
  # what we're searching for.
  #
  # Returns String.
  def munged_phrase
    escaped_query = Search.escape_characters(params.fetch(:q, "").strip)
    return "in:number #{escaped_query[1..]}" if escaped_query.start_with?("#")

    "in:title #{escaped_query.presence || "*"}"
  end

  def require_current_issue
    render_404 unless current_issue
  end

  def require_current_block
    render_404 unless current_block
  end

  def require_tasklist_block
    render_404 unless owner.feature_enabled?(:tasklist_block)
  end

  memoize def current_issue # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    current_repository.issues.find_by(number: params[:id].to_i)
  end

  memoize def resource_owner
    current_repository.owner
  end

  def current_block # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_block if defined?(@current_block)
    block_id = params[:uuid]
    tracking_blocks = current_issue.remote_tracking_blocks
    @current_block = if tracking_blocks
      if GitHub.flipper[:tasklist_block_precache].enabled?(current_repository.owner)
        return tracking_blocks[block_id.to_i]
      end
      tracking_blocks.find { |block| block&.key&.primaryKey&.uuid == block_id }
    end
  end

  # Returns Array of issues to be excluded from the autocomplete query.
  def hierarchy_child_ids
    current_block.issues&.collect { |issue| issue&.key&.itemId }
  end

  def valid_hit_type?(hit)
    return true if Elastomer.get_index_name_from_result(hit) == "issues"

    pr_support_enabled?
  end

  def pr_support_enabled?
    GitHub.flipper[:tasklist_block].enabled?(resource_owner)
  end
end
