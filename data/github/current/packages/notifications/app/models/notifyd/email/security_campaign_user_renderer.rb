# typed: strict
# frozen_string_literal: true

module Notifyd
  module Email
    class SecurityCampaignUserRenderer

      include ActionView::Helpers::NumberHelper
      include ActionView::Helpers::TextHelper
      include GitHub::Memoizer

      sig { returns(SecurityCampaigns::SecurityCampaignUser) }
      attr_reader :subject

      sig { returns(SecurityCampaigns::SecurityCampaign) }
      attr_reader :security_campaign

      sig { returns(User) }
      attr_reader :user

      sig { returns(User) }
      attr_reader :actor

      sig { returns(Operations::SecurityCampaignUserOperation) }
      attr_reader :operation

      sig { returns(T::Hash[Integer, Integer]) }
      attr_reader :alert_counts_by_repo

      sig { params(subject: SecurityCampaigns::SecurityCampaignUser, actor: ::User, operation: Operations::SecurityCampaignUserOperation, alert_counts_by_repo: T::Hash[Integer, Integer]).void }
      def initialize(subject:, actor:, operation:, alert_counts_by_repo:)
        @subject = subject
        @security_campaign = T.let(T.must(subject.security_campaign), SecurityCampaigns::SecurityCampaign)
        @user = T.let(T.must(subject.user), User)
        @actor = actor
        @operation = operation
        @alert_counts_by_repo = alert_counts_by_repo
      end

      sig { returns(Notifyd::Proto::Layouts::Email::Basic) }
      def render
        to = NoReplyAddress.new(name: user.name, handle: T.must(@security_campaign.organization).display_login)
        reasons_explainer = ReasonsExplainer.new
        unsubscribe_url_templates = UnsubscribeUrlTemplates.new

        Notifyd::Proto::Layouts::Email::Basic.new(
          headers: headers,
          from: email_from,
          to: to.serialize,
          subject: email_subject,
          body: html_body,
          text_body: text_body,
          unsubscribe_url_templates: unsubscribe_url_templates.serialize,
          url: security_campaign_org_url,
          reasons_to_words: reasons_explainer.serialize,
        )
      end

      private

      sig { returns(String) }
      def html_body
        html_template_file = Rails.root.join("packages", "notifications", "app", "models", "notifyd", "email", "templates", "security_campaign_user", "#{template_name}.html.erb")

        ERB.new(File.read(html_template_file)).result(binding)
      end

      sig { returns(String) }
      def text_body
        text_template_file = Rails.root.join("packages", "notifications", "app", "models", "notifyd", "email", "templates", "security_campaign_user", "#{template_name}.text.erb")

        ERB.new(File.read(text_template_file), trim_mode: "%<>").result(binding)
      end

      sig { returns(Notifyd::Proto::Layouts::Email::From) }
      def email_from
        Notifyd::Proto::Layouts::Email::From.new(name: "GitHub", email: "noreply@noreply.#{GitHub.urls.smtp_domain}")
      end

      sig { returns(T::Hash[String, String]) }
      def headers
        EmailHeaders.new(subject, security_campaign.organization, actor.display_login).build
      end

      sig { returns(String) }
      def template_name
        operation.serialize
      end

      sig { returns(String) }
      def email_subject
        case operation
        when Operations::SecurityCampaignUserOperation::Create
          "[#{organization_display_login}] A new security campaign has been opened on your repositories"
        when Operations::SecurityCampaignUserOperation::Overdue
          "[#{organization_display_login}] A security campaign on your repositories is overdue"
        else
          raise ArgumentError, "Unknown operation: #{operation}"
        end
      end

      sig { returns(String) }
      def security_campaign_org_url
        Rails.application.routes.url_helpers.security_center_security_campaign_url(org: @security_campaign.organization, number: @security_campaign.number, email_source: "security_campaign_#{operation.serialize}", host: GitHub.url)
      end

      sig { returns(String) }
      def security_campaigns_help_url
        SecurityCampaigns.fixing_alerts_docs_url
      end

      sig { params(manager: T.any(User, Team)).returns(String) }
      def manager_name(manager)
        if manager.is_a?(User)
          manager.display_login
        else
          "#{T.must(manager.organization).display_login}/#{manager.slug}"
        end
      end

      sig { params(manager: T.any(User, Team)).returns(String) }
      def manager_url(manager)
        if manager.is_a?(User)
          Rails.application.routes.url_helpers.user_url(manager, host: GitHub.url)
        else
          Rails.application.routes.url_helpers.team_url(manager.organization, manager, host: GitHub.url)
        end
      end

      sig { returns(T::Enumerable[T.any(User, Team)]) }
      memoize def managers
        user_visible_teams = security_campaign.organization&.visible_teams_for(user).to_a || []
        team_manager_teams = security_campaign.team_manager_teams.select { |team| user_visible_teams.include?(team) }

        (security_campaign.user_manager_users + team_manager_teams).compact.sort_by do |manager|
          if manager.is_a?(User)
            manager.display_login
          else
            manager.slug
          end
        end
      end

      sig { returns(Integer) }
      memoize def alerts_count
        case operation
        when Operations::SecurityCampaignUserOperation::Create
          # For creation events, we don't need to check whether these alerts are still open.
          repo_counts_by_campaign.open_count
        when Operations::SecurityCampaignUserOperation::Overdue
          counts = alert_counts_by_repo.map do |repo_id, count|
            enabled_repository_ids.include?(repo_id) ? count : 0
          end
          counts.sum
        else
          raise ArgumentError, "Unknown operation: #{operation}"
        end
      end

      sig { returns(T::Array[Integer]) }
      memoize def enabled_repository_ids
        repository_ids = repo_counts_by_campaign.repository_counts.map(&:repository_id)
        SecurityCampaignUserHelper.enabled_repository_ids(user: user, security_campaign: @security_campaign, repository_ids:)
      end

      sig { returns(Turboscan::Proto::CountsByRepoResponse) }
      memoize def repo_counts_by_campaign
        if security_campaign.secret_scanning?
          query_service = SecretScanning::AlertQueryService.for_organization(
            current_user: user,
            user_session: nil,
            organization: T.must(security_campaign.organization),
            security_campaign_ids: [security_campaign.id],
          )
          counts_by_repo, has_error, _ = query_service.counts_by_repo
          if has_error
            raise StandardError.new("Failed to fetch secret scanning repo counts")
          end

          # Convert SecretScanning repo counts into Turboscan::Proto::CountsByRepoResponse
          # TODO: remove conversion https://github.com/github/secret-scanning/issues/14381
          repo_counts = counts_by_repo.map do |repo|
            Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new({
              repository_id: repo.repository_id,
              open_count: repo.unresolved_count,
              closed_count: repo.resolved_count,
            })
          end

          Turboscan::Proto::CountsByRepoResponse.new({
            open_count: repo_counts.sum(&:open_count),
            closed_count: repo_counts.sum(&:closed_count),
            repository_counts: repo_counts,
          })
        else
          query_service = CodeScanning::AlertQueryService.for_organization(
            user:,
            user_session: nil,
            organization: T.must(security_campaign.organization),
            security_campaign_ids: [security_campaign.id],
          )
          _, has_error, alerts_response = query_service.counts_by_repo

          if has_error
            raise StandardError.new(alerts_response&.error&.msg || "No response when fetching alerts")
          end
          alerts_response.data
        end
      end

      sig { params(path: String).returns(String) }
      def image_url(path)
        StaticAssetPaths.static_asset_path("/images/email#{path}", mailer: true)
      end

      sig { returns(String) }
      def alert_type
        if security_campaign.secret_scanning?
          "Secrets"
        else
          "Code"
        end
      end

      sig { returns(T.nilable(String)) }
      def campaign_description
        description = security_campaign.description
        return nil if description.blank?
        T.cast(description, String)
      end

      sig { returns(String) }
      def organization_display_login
        T.must(security_campaign.organization).display_login
      end
    end
  end
end
