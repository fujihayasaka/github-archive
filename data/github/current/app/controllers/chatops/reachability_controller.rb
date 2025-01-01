# typed: true
# frozen_string_literal: true

require "chatops-controller"

class Chatops::ReachabilityController < ApplicationController # rubocop:disable Rails/ModuleNaming
  include ::Chatops::Controller
  include ::GitHubChatopsExtensions::Checks::Includable::Fido
  include ::GitHubChatopsExtensions::Checks::Includable::Entitlements
  include ::GitHubChatopsExtensions::Checks::Includable::Room

  # CAP not required on chatops controllers
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:list]

  chatops_namespace :reachability
  chatops_help "Commands for working with Reachability chatops"
  chatops_error_response "Try re-running the command or ask for help in [#team-reachability](https://github-grid.enterprise.slack.com/archives/C049DECNG83)."

  ALLOWED_ROOMS = ["#team-reachability-ops"].freeze
  ALLOWED_TEAMS = ["pizza_teams/team-reachability"].freeze
  CONTROLLED_ACTIONS = [:analyze].freeze

  before_action :require_fido_2fa_when_confirming, only: CONTROLLED_ACTIONS
  before_action -> { T.bind(self, Chatops::ReachabilityController); require_in_room(ALLOWED_ROOMS) }, only: CONTROLLED_ACTIONS
  before_action -> { T.bind(self, Chatops::ReachabilityController); require_ldap_entitlement(ALLOWED_TEAMS) }, only: CONTROLLED_ACTIONS

  chatop :analyze,
    /analyze(?:\s+(?<nwo_or_id>\S+))/,
    "analyze <repo NWO or repo id> - run analysis on a repo" do
      nwo_or_id = jsonrpc_params.require(:nwo_or_id)
      repo = nil
      # find by repo id first if provided
      if nwo_or_id.match?(/\A[0-9]+\Z/)
        repo = Repository.find_by(id: nwo_or_id)
      # find by nwo if provided
      elsif nwo_or_id.match?(/\A[\w-]+\/[\w-]+\z/)
        repo = Repository.nwo(nwo_or_id)
      else
        chatop_send("Invalid repo nwo or id: #{nwo_or_id}")
        return
      end

      if repo.nil?
        chatop_send("Repository #{nwo_or_id} not found")
        return
      end

      begin
        analysis = ReachabilityAnalysis.create!(repository: repo, sha: repo.default_oid, state: :requested)
      rescue ActiveRecord::RecordInvalid => e
        chatop_send("Could not create reachability analysis for #{repo.name_with_owner}: #{e.message}")
        return
      end
      ReachabilityAnalysisJob.perform_later(repo.id, actor: params[:user])
      analysis.set_enqueued

      chatop_send("Reachability analysis has been enqueued for #{repo.name_with_owner}. View Actions runs [here](#{repo.permalink}/actions).")
      GitHub.logger.info("reachability analyze command triggered", "gh.repo.nwo" => repo.nwo, "gh.user.login" => params[:user], "gh.actions.workflow.path" => "#{repo.permalink}/actions")
    end

  chatop :test,
    /test/,
    "test - simple nonrestricted test command" do
      chatop_send("testing!")
    end

  private

  def verify_authenticity_token?
    false # robots do this
  end

  def require_fido_2fa_when_confirming
    return unless jsonrpc_params[:confirm].present?

    require_fido_2fa
  end
end
