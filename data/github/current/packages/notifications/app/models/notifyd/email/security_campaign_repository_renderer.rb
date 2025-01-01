# typed: strict
# frozen_string_literal: true

module Notifyd
  module Email
    class SecurityCampaignRepositoryRenderer

      include ActionView::Helpers::NumberHelper
      include ActionView::Helpers::TextHelper
      include GitHub::Memoizer

      sig { returns(SecurityCampaigns::SecurityCampaignRepository) }
      attr_reader :subject

      sig { returns(SecurityCampaigns::SecurityCampaign) }
      attr_reader :security_campaign

      sig { returns(Repository) }
      attr_reader :repository

      sig { returns(User) }
      attr_reader :manager

      sig { returns(User) }
      attr_reader :actor

      sig { returns(Operations::SecurityCampaignRepositoryOperation) }
      attr_reader :operation

      sig { returns(Context) }
      attr_reader :context

      sig { params(subject: SecurityCampaigns::SecurityCampaignRepository, actor: ::User, operation: Operations::SecurityCampaignRepositoryOperation, context: Context).void }
      def initialize(subject:, actor:, operation:, context:)
        @subject = subject
        @security_campaign = T.let(T.must(subject.security_campaign), SecurityCampaigns::SecurityCampaign)
        @repository = T.let(T.must(subject.repository), Repository)
        @manager = T.let(@security_campaign.safe_manager, User)
        @actor = actor
        @operation = operation
        @context = context
      end

      sig { returns(Notifyd::Proto::Layouts::Email::Basic) }
      def render
        to = NoReplyAddress.new(name: repository.name_with_display_owner, handle: repository.to_s || "")
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
          url: security_campaign_repository_url,
          reasons_to_words: reasons_explainer.serialize,
        )
      end

      private

      sig { returns(String) }
      def html_body
        html_template_file = Rails.root.join("packages", "notifications", "app", "models", "notifyd", "email", "templates", "security_campaign_repository", "#{template_name}.html.erb")

        ERB.new(File.read(html_template_file)).result(binding)
      end

      sig { returns(String) }
      def text_body
        text_template_file = Rails.root.join("packages", "notifications", "app", "models", "notifyd", "email", "templates", "security_campaign_repository", "#{template_name}.text.erb")

        ERB.new(File.read(text_template_file), trim_mode: "%<>").result(binding)
      end

      sig { returns(Notifyd::Proto::Layouts::Email::From) }
      def email_from
        Notifyd::Proto::Layouts::Email::From.new(name: "GitHub", email: "noreply@noreply.#{GitHub.urls.smtp_domain}")
      end

      sig { returns(T::Hash[String, String]) }
      def headers
        EmailHeaders.new(subject, repository, actor.display_login).build
      end

      sig { returns(String) }
      def template_name
        operation.serialize
      end

      sig { returns(String) }
      def email_subject
        case operation
        when Operations::SecurityCampaignRepositoryOperation::Create
          "[#{repository.name_with_display_owner}] Security campaign #{security_campaign.name} has been opened on your repository"
        when Operations::SecurityCampaignRepositoryOperation::Overdue
          "[#{repository.name_with_display_owner}] Security campaign #{security_campaign.name} is overdue"
        else
          raise ArgumentError, "Unknown operation: #{operation}"
        end
      end

      sig { returns(String) }
      def security_campaign_repository_url
        Rails.application.routes.url_helpers.repository_security_campaign_url(repository: @repository, user_id: @repository.owner_display_login, number: @security_campaign.number, email_source: "security_campaign_#{operation.serialize}", host: GitHub.url)
      end

      sig { returns(String) }
      def security_campaigns_help_url
        SecurityCampaigns.fixing_alerts_docs_url(T.must(@repository.owner)) || ""
      end

      sig { returns(String) }
      def manager_url
        Rails.application.routes.url_helpers.user_url(manager, host: GitHub.url)
      end

      sig { returns(Integer) }
      memoize def alerts_count
        case operation
        when Operations::SecurityCampaignRepositoryOperation::Create
          # For creation events, we don't need to check whether these alerts are still open.
          SecurityCampaigns::SecurityCampaignAlert.where(security_campaign: @security_campaign, repository: @repository).count
        when Operations::SecurityCampaignRepositoryOperation::Overdue
          context.fetch(:open_alerts_count)
        else
          raise ArgumentError, "Unknown operation: #{operation}"
        end
      end
    end
  end
end
