# typed: strict
# frozen_string_literal: true

module Repos
  module CodeViewSidebar
    class CodeViewSidebar
      include UrlHelpers
      include UrlHelper
      include GitHub::RouteHelpers
      include EscapeHelper

      sig { params(view_model: Files::OverviewView, current_user: T.nilable(User), current_repository: Repository).void }
      def initialize(view_model:, current_user:, current_repository:)
        @view_model = view_model
        @current_user = current_user
        @current_repository = current_repository
      end

      sig { returns(AboutPayload) }
      def about_payload
        owner = @current_repository.owner

        AboutPayload.new(
          description: @current_repository.description.presence,
          website: safe_uri(@view_model.website.presence),
          topics: @view_model.topics.sort_by(&:name).map { |t| Topic.new(name: t.name) },
          showInsights: @view_model.show_insights?,
          stargazerCount: @current_repository.stargazer_count || 0,
          watcherCount: @current_repository.watchers_count,
          forksCount: @current_repository.forks_count,
          stargazersPath: gh_stargazers_path(@current_repository),
          watchersPath: gh_watchers_path(@current_repository),
          forkNetworkPath: gh_fork_network_path(@current_repository),
          activityPath: @view_model.show_insights? ? activity_index_path(owner, @current_repository) : nil,
          customPropertiesPath: custom_properties_path(owner),
          auditLogPath: audit_log_path(owner),
          reportPath: report_path(owner),
          canEditMetadata: @view_model.can_edit_metadata?,
          ownerLogin: owner&.display_login || "",
          repoName: @current_repository.name,
          isOrg: owner&.organization? || false,
      )
      end

      private

      sig { params(owner: T.nilable(User)).returns(T.nilable(String)) }
      def custom_properties_path(owner)
        return nil unless owner&.organization? && @view_model.show_insights?

        repository_custom_properties_overview_path(owner, @current_repository)
      end

      sig { params(owner: T.nilable(User)).returns(T.nilable(String)) }
      def audit_log_path(owner)
        return nil unless @view_model.can_view_organization_audit_log_link?

        settings_org_audit_log_path(owner, q: "repo:#{@current_repository.name_with_display_owner}")
      end

      sig { params(owner: T.nilable(User)).returns(T.nilable(String)) }
      def report_path(owner)
        return nil unless @current_repository.can_report?(@current_user)

        flavored_contact_path(
          flavor: "report-content",
          report: "#{owner&.display_login} (user)",
          content_url: "#{GitHub.url}#{repository_path(@current_repository)}",
        )
      end

    end

    ## Payload Structs

    class Topic < T::Struct
      const :name, String
    end

    class AboutPayload < T::Struct
      const :description, T.nilable(String)
      const :website, T.nilable(String)
      const :topics, T::Array[Topic]
      const :showInsights, T::Boolean
      const :stargazerCount, Integer
      const :watcherCount, Integer
      const :forksCount, Integer
      const :stargazersPath, String
      const :watchersPath, String
      const :forkNetworkPath, String
      const :activityPath, T.nilable(String)
      const :customPropertiesPath, T.nilable(String)
      const :auditLogPath, T.nilable(String)
      const :reportPath, T.nilable(String)
      const :canEditMetadata, T::Boolean
      const :ownerLogin, String
      const :repoName, String
      const :isOrg, T::Boolean
    end

  end
end
