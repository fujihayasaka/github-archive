# typed: true
# frozen_string_literal: true

require "chatops-controller"
require "github_chatops_extensions"
require "github/config/kv"
require "json"


class Chatops::MemexController < ApplicationController
  include ::Chatops::Controller
  include ::GitHubChatopsExtensions::Checks::Includable::Room
  include ::GitHubChatopsExtensions::Checks::Includable::Fido
  include ::GitHubChatopsExtensions::Checks::Includable::Entitlements

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:list]

  ALLOWED_ROOMS = ["#memex-ops"].freeze
  ALLOWED_TEAMS = ["org_teams/auto-ahalliop-a409f8454065796264"].freeze
  CONTROLLED_ACTIONS = [:enterprise].freeze
  MEMEX_RELEASE_DISPATCH_EVENT = "memex_create_release".freeze
  MEMEX_REPO_ID = 221238710

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action -> { T.bind(self, Chatops::MemexController); require_in_room(ALLOWED_ROOMS) }, only: CONTROLLED_ACTIONS
  before_action :require_fido_2fa_when_confirming, only: CONTROLLED_ACTIONS
  before_action -> { T.bind(self, Chatops::MemexController); require_ldap_entitlement(ALLOWED_TEAMS) }, only: CONTROLLED_ACTIONS
  # Catch validation errors that are most likely user error, and not a bug or server error
  # ActiveModel::ValidationError is in case of errors with validating the proposed Block
  # ActionController::ParameterMissing is in case of missing chatops parameters
  rescue_from "ActiveModel::ValidationError", "ActionController::ParameterMissing" do |e|
    T.bind(self, Chatops::MemexController)
    # Since we're rescuing this error, we should still report it to Sentry in case it still needs investigation
    Failbot.report e
    chatop_send "#{e.message}. More information is available [in Sentry](https://sentry.io/organizations/github/issues/?query=is%3Aunresolved+controller%3A%22Chatops%3A%3AMemexController%22)"
  end

  chatops_namespace :memex
  chatops_help "View and manage memex release versions"
  chatops_error_response "More information is available [in Sentry](https://sentry.io/organizations/github/issues/?query=is%3Aunresolved+controller%3A%22Chatops%3A%3AMemexController%22)"

  chatop :enterprise, /enterprise release\s+(?<version>([0-9]+)\.[0-9]+)?/, "enterprise [release <version>] [--test] - Prepares a release to patch stable for a supplied enterprise version - for example 3.7" do
    params = jsonrpc_params.permit(:version, :test, :message_id)
    version = params[:version]
    test_release = params[:test]
    enterprise_branch = "enterprise-#{version}-release"
    dispatch_release_event(target_package: "stable", promote_latest: false, release_branch: enterprise_branch, test_release: test_release, enterprise_version: version, release_type: "patch")
    chatop_send "Okay <@#{initiator}>, I've kicked off that #{test_release && "test "}release for stable on enterprise #{version}. You will be notified when the release workflow is complete."
  end

  private

  memoize def current_actor
    User.find_by!(login: params[:user])
  end

  memoize def memex_repo
    Repositories::Public.find_active!(MEMEX_REPO_ID)
  end

  def initiator
    params.fetch(:mention_slug)
  end

  def require_fido_2fa_when_confirming
    return unless jsonrpc_params[:confirm].present?

    require_fido_2fa
  end

  def dispatch_release_event(target_package:, promote_latest:, test_release: false, release_type: nil, release_branch: nil, enterprise_version: nil)
    release_branch ||= memex_repo.default_branch
    memex_repo.dispatch_event(
      current_actor.id,
      MEMEX_RELEASE_DISPATCH_EVENT,
      {
        release_type: release_type,
        target_package: target_package,
        promote_latest: promote_latest,
        release_branch: release_branch,
        enterprise_version: enterprise_version,
        test: !test_release.blank? && test_release != "false",
      }
    )
  end

  # START: conditional access opt-outs
  private def verify_authenticity_token?
    false # robots do this
  end
  # END: conditional access opt-outs
end
