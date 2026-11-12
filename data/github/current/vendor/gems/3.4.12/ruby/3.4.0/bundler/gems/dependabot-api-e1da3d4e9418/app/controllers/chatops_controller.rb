# frozen_string_literal: true

require "github_chatops_extensions"

class ChatopsController < ActionController::API
  include ::Chatops::Controller
  include ::GitHubChatopsExtensions::Checks::Includable::Fido
  include ::GitHubChatopsExtensions::Checks::Includable::Room

  class CommandError < StandardError; end

  before_action :disallow_enterprise
  # rubocop:disable Rails/LexicallyScopedActionFilter
  before_action :ensure_permitted_room_id, except: %i(list logs)
  # rubocop:enable Rails/LexicallyScopedActionFilter

  rescue_from "CommandError" do |exception|
    jsonrpc_failure(exception.message)
  end

  def ensure_permitted_room_id
    # Permit calls from 'gh-rpc' on a developer shell
    return true if params[:room_id] == "ssh"

    require_in_room(["#dependabot-ops", "#dependabot-chatops"])
  end

  def disallow_enterprise
    jsonrpc_method_not_found if Dependabot.enterprise?
  end

  chatops_namespace :dependabot

  # See app/controllers/concerns/
  include ChatopAccountFeatures
  include ChatopActions
  include ChatopDependabotActions
  include ChatopDisable
  include ChatopHydro
  include ChatopIgnoreConditions
  include ChatopInfo
  include ChatopJob
  include ChatopLogs
  include ChatopRepoFeatures
  include ChatopRepoPause
  include ChatopResync
  include ChatopRetry
  include ChatopRolloutFeatures
  include ChatopSetup
  include ChatopThrottler
  include ChatopUpdateJobErrors
  include ChatopUpdaterEcosystem
  include ChatopValidateConfigFile
  include ChatopWorkflowPausing

  def valid_nwo?(nwo)
    nwo.split("/").count == 2
  end

  def find_by_nwo!(nwo, tenant_slug)
    github_login, repo_name = nwo.split("/")

    raise CommandError, "`#{nwo}` doesn't seem to be a Name With Owner." unless repo_name

    account = find_account!(github_login, tenant_slug)
    active_repos = account.repos.where(name: repo_name).active.uniq
    if active_repos.many?
      # This is unexpected and likely a bug, so we want to know about it
      duplicate_repo_ids = active_repos.pluck(:id).join(", ")
      raise CommandError,
            "`#{account.github_login}` has more than one active repo with that name: #{duplicate_repo_ids}"
    end

    # this is the typical case
    return active_repos.first if active_repos.present?

    # fallback to returning a recent inactive repo, in case of investigating old repos for example
    account.repos.order(id: :desc).find_by!(name: repo_name)
  rescue ActiveRecord::RecordNotFound
    raise CommandError, "Repository `#{nwo}` not found."
  end

  def find_account!(github_login, tenant_slug)
    tenant = find_tenant!(tenant_slug)
    Account.order(id: :desc).find_by!(github_login: github_login, tenant: tenant)
  rescue ActiveRecord::RecordNotFound
    raise CommandError, "Account `#{github_login}` not found, do you need to specify a `--tenant`?" if tenant_slug.nil?

    raise CommandError, "Account `#{github_login}` with tenant #{tenant_slug} not found."
  end

  def find_tenant!(slug)
    return nil if slug.blank?

    Tenant.find_by!(slug: slug)
  rescue ActiveRecord::RecordNotFound
    raise CommandError, "Tenant `#{slug}` not found on this stamp."
  end

  # Overrides Chatops::Controller to add a default thread style
  def jsonrpc_success(message, options: {})
    options[:thread_style] = ::Chatops::THREAD_STYLES[:threaded] unless options.key?(:thread_style)
    response = { result: message.to_s }
    # do not allow options to override message
    options.delete(:result)
    jsonrpc_response response.merge(options)
  end
end
