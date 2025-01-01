# typed: strict
# frozen_string_literal: true

module Notifyd
  module Email
    class MemberFeatureRequestRenderer

      Layout = ::Notifyd::Proto::Layouts::Email

      sig { returns(MemberFeatureRequest::Notification) }
      attr_reader :subject

      sig { returns(T.any(::Organization, ::Business)) }
      attr_reader :entity

      sig { returns(::User) }
      attr_reader :admin

      sig { returns(MemberFeatureRequest::Feature) }
      attr_reader :feature_request

      sig { returns(Integer) }
      attr_reader :feature_request_count

      sig { returns(Context) }
      attr_reader :context

      sig { returns(Copilot::Organization) }
      attr_reader :copilot_organization

      sig { params(subject: MemberFeatureRequest::Notification, context: T.nilable(Context)).void }
      def initialize(subject, context)
        @subject = T.let(subject, MemberFeatureRequest::Notification)
        @entity = T.let(subject.entity, T.any(::Organization, ::Business))
        @admin = T.let(T.must(subject.user), ::User)
        @feature_request = T.let(T.must(MemberFeatureRequest::Feature.from_string(subject.feature)), MemberFeatureRequest::Feature)
        @feature_request_count = T.let(subject.feature_request_count, Integer)
        @context = T.let(context || {}, Context)

        if @entity.is_a?(::Organization)
          @copilot_organization = T.let(Copilot::Organization.new(@entity), Copilot::Organization)
        end
      end

      sig { returns(Layout::Basic) }
      def render
        unsubscribe_url_templates = UnsubscribeUrlTemplates.new

        Layout::Basic.new(
          headers: email_headers.build,
          from: email_from,
          to: ApplicationMailer::Helpers.user_email(admin, GitHub.newsies.email(admin, entity).value),
          subject: email_subject,
          body: html_body,
          text_body: text_body,
          unsubscribe_url_templates: unsubscribe_url_templates.serialize,
          url: member_feature_requests_settings_url
        )
      end

      private

      sig { returns(String) }
      def member_feature_requests_feature_url
        case entity
        when Business
          url_helpers.settings_copilot_enterprise_url(entity, host: GitHub.url)
        when Organization
          url_helpers.organization_settings_member_feature_requests_url(entity, host: GitHub.url, anchor: feature_request)
        end
      end

      sig { returns(String) }
      def member_feature_requests_settings_url
        case entity
        when Business
          url_helpers.settings_notification_preferences_url(host: GitHub.url)
        when Organization
          url_helpers.organization_settings_member_feature_requests_url(entity, host: GitHub.url)
        end
      end

      sig { returns(String) }
      def copilot_seat_management_url
        url_helpers.settings_org_copilot_seat_management_url(entity, host: GitHub.url)
      end

      sig { returns(T.untyped) }
      def url_helpers
        Rails.application.routes.url_helpers
      end

      sig { returns(String) }
      def html_body
        html_template_file = Rails.root.join("packages", "notifications", "app", "models", "notifyd", "email", "templates", "member_feature_request", "#{email_file_name}.html.erb")

        ERB.new(File.read(html_template_file)).result(binding)
      end

      sig { returns(String) }
      def text_body
        text_template_file = Rails.root.join("packages", "notifications", "app", "models", "notifyd", "email", "templates", "member_feature_request", "#{email_file_name}.text.erb")

        ERB.new(File.read(text_template_file), trim_mode: "%<>").result(binding)
      end

      sig { returns(Layout::From) }
      def email_from
        Layout::From.new(name: "GitHub", email: "noreply@noreply.#{GitHub.urls.smtp_domain}")
      end

      sig { returns(Notifyd::EmailHeaders) }
      def email_headers
        EmailHeaders.new(subject, admin, context[:actor_login])
      end

      sig { returns(String) }
      def email_subject
        requesters = entity.is_a?(Business) ? "admins" : "members"
        "[#{entity.safe_profile_name}] New requests from #{requesters} for #{feature_request.formatted_text}"
      end

      sig { returns(String) }
      def email_file_name
        @entity.is_a?(Business) ? "enterprise_notification" : "notification"
      end
    end
  end
end
