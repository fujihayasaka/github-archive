# typed: true
# frozen_string_literal: true

class RepositoryStatsController < ApplicationController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  # This controller does not access any restful resources, so there are no conditional access checks to do.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :parse_json_params
  allow_verified_fetch only: [:create]

  def create
    payload = stats_payload
    GlobalInstrumenter.instrument("repository_ui_event", payload)
    # whether the stats call succeeds or not, return :ok
    render(json: payload, status: :ok)
  rescue ActionController::UnpermittedParameters
    render(json: { success: false }, status: :unprocessable_entity)
  end

  private

  def stats_payload
    stats_params.to_h.slice(*STATS_PARAMS)
  end

  def stats_params
    params.permit(*STATS_PARAMS, *OTHER_PARAMS, context: CONTEXT_ALLOWLIST)
  end

  STATS_PARAMS = [
    :target,
    :interaction,
    :performed_at,
    :repository_id,
    :repository_nwo,
    :repository_public,
    :repository_is_fork,
    :react_app,
    :actor_id,
    :actor_login,
    :url,
    :user_agent,
    :browser_width,
    :browser_languages
  ]

  OTHER_PARAMS = [:user_id, :repository]

  CONTEXT_ALLOWLIST = %w[
    find-file-base-count
    find-file-results-count
    find-file-duration-ms
  ]
end
