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
      attr_reader :manager

      sig { returns(User) }
      attr_reader :actor

      sig { returns(Operations::SecurityCampaignUserOperation) }
      attr_reader :operation

      sig { returns(Context) }
      attr_reader :context

      sig { params(subject: SecurityCampaigns::SecurityCampaignUser, actor: ::User, operation: Operations::SecurityCampaignUserOperation, context: Context).void }
      def initialize(subject:, actor:, operation:, context:)
        @subject = subject
        @security_campaign = T.let(T.must(subject.security_campaign), SecurityCampaigns::SecurityCampaign)
        @user = T.let(T.must(subject.user), User)
        @manager = T.let(@security_campaign.safe_manager, User)
        @actor = actor
        @operation = operation
        @context = context
      end

      sig { returns(Notifyd::Proto::Layouts::Email::Basic) }
      def render
        to = NoReplyAddress.new(name: security_campaign.name, handle: T.must(security_campaign.manager).name)
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
          url: security_campaign_user_url,
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
          "[#{actor.name}] Security campaign #{security_campaign.name} has been opened on your repositories"
        when Operations::SecurityCampaignUserOperation::Overdue
          "[#{actor.name}] Security campaign #{security_campaign.name} is overdue"
        else
          raise ArgumentError, "Unknown operation: #{operation}"
        end
      end

      sig { returns(String) }
      def security_campaign_user_url
        Rails.application.routes.url_helpers.security_center_security_campaign_url(org: @security_campaign.organization, number: @security_campaign.number, email_source: "security_campaign_#{operation.serialize}", host: GitHub.url)
      end

      sig { returns(String) }
      def security_campaigns_help_url
        SecurityCampaigns.fixing_alerts_docs_url(user) || ""
      end

      sig { returns(String) }
      def manager_url
        Rails.application.routes.url_helpers.user_url(manager, host: GitHub.url)
      end

      sig { returns(Integer) }
      memoize def alerts_count
        # For creation events, we don't need to check whether these alerts are still open.
        enabled_repository_ids.each_slice(1000).map do |repository_ids_slice|
          SecurityCampaigns::SecurityCampaignAlert.where(security_campaign: @security_campaign, repository_id: repository_ids_slice).count
        end.sum
      end

      sig { returns(T::Array[Repository]) }
      memoize def enabled_repositories
        Repository.where(id: enabled_repository_ids).to_a
      end

      sig { returns(T::Array[Integer]) }
      memoize def enabled_repository_ids
        SecurityCampaignUserHelper.enabled_repository_ids(user: user, security_campaign: @security_campaign)
      end

      sig { params(repository: Repository).returns(String) }
      def campaign_url_by_repository(repository:)
        Rails.application.routes.url_helpers.repository_security_campaign_url(
          repository: repository,
          user_id: repository.owner_display_login,
          number: @security_campaign.number,
          email_source: "security_campaign_#{operation.serialize}",
          host: GitHub.url,
        )
      end
    end
  end
end
