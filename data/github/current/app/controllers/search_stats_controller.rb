# typed: true
# frozen_string_literal: true

class SearchStatsController < ApplicationController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  # This controller does not access any customer-owned resources, so there are no conditional access checks to do.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :parse_json_params
  allow_verified_fetch only: [:create]

  def create
    payload = stats_payload
    GlobalInstrumenter.instrument("search_ui_event", payload)
    # whether the stats call succeeds or not, return :ok
    render(json: { success: true }, status: :ok)
  rescue ActionController::UnpermittedParameters
    render(json: { success: false }, status: :unprocessable_entity)
  end

  private

  memoize def stats_payload
    stats_params.to_h.slice(*STATS_PARAMS)
  end

  memoize def stats_params
    params.permit(*STATS_PARAMS, *OTHER_PARAMS, context: CONTEXT_ALLOWLIST)
  end

  STATS_PARAMS = [
    :target,
    :interaction,
    :performed_at,
    :query_id,
    :page_index,
    :result_index,
    :result_type,
    :result_path,
    :result_language,
    :result_line_number,
    :result_ref_name,
    :result_commit_sha,
    :result_blob_sha,
    :result_repo_nwo,
    :react_app,
    :actor_id,
    :actor_login,
    :url,
    :user_agent,
    :browser_width,
    :browser_languages
  ]

  OTHER_PARAMS = []

  CONTEXT_ALLOWLIST = []
end
