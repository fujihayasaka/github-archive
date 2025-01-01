# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class GeneratePortalPartnerInfo < Command
    include GitHub::Memoizer
    include UrlHelpers
    include UrlHelper

    COPILOT_EXTENSION_ID = "GitHub.copilot"

    attr_reader :user, :codespace, :github_token, :github_token_valid_after, :user_settings, :connection

    def initialize(user:, codespace:, github_token:, github_token_valid_after:, user_settings:, connection:, host: GitHub.host_name)
      @user = user
      @codespace = codespace
      @github_token = github_token
      @github_token_valid_after = github_token_valid_after
      @user_settings = user_settings
      @host = host
      @connection = connection
    end

    def perform
      credentials = [
        {
          token: github_token,
          host: @host,
          validAfter: github_token_valid_after
        }
      ]

      payload = {
        partnerName: "github",
        managementPortalUrl: auth_redirect_codespaces_url(host: @host),
        codespaceId: codespace.guid,
        connectionInfo: connection,
        credentials: credentials,
        favicon: {
          stable: "https://github.com/favicons/favicon-codespaces.svg",
          insider: "https://github.com/favicons/favicon-codespacesinsider.svg"
        },
        featureFlags: Codespaces::Vscs.feature_flags(user),
        vscodeSettings: vscode_settings,
        gitHubApiUrl: Codespaces.monolith_url_builder.api_url,
        workbenchType: "codespaces",
        name: codespace.name,
        displayName: codespace.safe_display_name,
        workspaceCustomizations: workspace_customizations,
      }

      if user&.feature_enabled?(:copilot_agent_mode)
        context = build_issue_context
        return payload unless context.present?
        payload[:agentContext] = context
      end

      payload
    end

    private

    def codespaces_home_url
      if codespace.pull_request_with_fallback.present?
        show_pull_request_url(codespace.repository.owner, codespace.repository, codespace.pull_request, host: @host)
      else
        repository_url(codespace.repository)
      end
    end

    def vscode_settings
      default_extensions = Codespaces::Settings::DEFAULT_EXTENSIONS.dup
      if Copilot::User.new(user).codespaces_demo_usage_allowed?(codespace)
        default_extensions << COPILOT_EXTENSION_ID
      end

      user_settings.vscode_settings(codespaces_home_url: codespaces_home_url, github_token: github_token, user: user, open_files_specified: open_files_specified?, default_extensions:)
    end

    def workspace_customizations
      # Avoid grabbing all of customizations.codespaces since it could be pretty big. Just grab the properties we
      # care about.
      {
        openFiles: codespace.dev_container&.dig("customizations", "codespaces", "openFiles"),
      }
    rescue Codespaces::DevContainer::ReadError => e
      nil
    end

    def open_files_specified?
      return false unless workspace_customizations
      !workspace_customizations[:openFiles].nil?
    end

    def cache_key
      @cache_key ||= "codespace:#{codespace.oid}:repository_id:#{codespace.repository.id}:issue_id"
    end

    def build_issue_context
      repository_id = codespace.repository.id

      cached_response = ActiveRecord::Base.connected_to(role: :reading) do
        Codespaces::Kv.store.get(cache_key).value { nil }
      end

      # cached_response will be nil for non-agent-mode codespaces or if the cached issue_id expired
      return unless cached_response.present?

      begin
        issue = Issue.find(cached_response) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      rescue ActiveRecord::RecordNotFound => e
        GitHub.logger.error(
          :exception => e,
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.repo.id" => repository_id,
          "gh.user.id" => user.id,
        )
        return { type: "error", data: "Failed to find the target issue" }
      end

      unless issue.readable_by?(user)
        return { type: "error", data: "User does not have access to view the issue" }
      end

      {
        type: "issueBody",
        data: issue.body,
      }
    end
  end
end
