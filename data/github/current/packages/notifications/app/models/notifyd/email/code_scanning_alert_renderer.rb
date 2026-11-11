# typed: strict
# frozen_string_literal: true

module Notifyd
  module Email
    class CodeScanningAlertRenderer
      sig { params(subject: CodeScanning::AlertEventNotification, actor: ::User, operation: Operations::CodeScanningAlertOperation, beacon_url: T.nilable(String), assignee: T.nilable(::User)).void }
      def initialize(subject:, actor:, operation:, beacon_url: "", assignee: nil)
        @subject = subject
        @actor = actor
        @operation = operation
        @assignee = assignee
        @beacon_url = beacon_url
      end

      sig { returns(Notifyd::Proto::Layouts::Email::Basic) }
      def render
        to = if @assignee.present?
          NoReplyAddress.new(name: @assignee.name, handle: T.must(@subject.repository).name_with_display_owner)
        else
          NoReplyAddress.new(name: T.must(@subject.repository).name_with_display_owner, handle: T.must(@subject.repository).to_s)
        end
        reasons_explainer = ReasonsExplainer.new
        unsubscribe_url_templates = UnsubscribeUrlTemplates.new

        Notifyd::Proto::Layouts::Email::Basic.new(
          headers: headers,
          from: email_from.serialize,
          to: to.serialize,
          subject: email_subject,
          body: html_body,
          text_body:,
          unsubscribe_url_templates: unsubscribe_url_templates.serialize,
          url: code_scanning_alert_url,
          reasons_to_words: reasons_explainer.serialize,
          beacon_url: @beacon_url,
        )
      end

      sig { returns(String) }
      def code_scanning_alert_url
        Rails.application.routes.url_helpers.repository_code_scanning_result_url(
          user_id: T.must(@subject.repository).owner_display_login,
          repository: @subject.repository,
          number: @subject.alert_number,
          email_source: "code_scanning_alert_#{@operation.serialize}",
          host: GitHub.url
        )
      end

      sig { returns(String) }
      def assignee_url
        UrlHelpers.user_url(@assignee, host: GitHub.url)
      end

      sig { returns(Integer) }
      def alert_number
        @subject.alert_number
      end

      private

      sig { returns(String) }
      def html_body
        html_template_file = Rails.root.join("packages", "notifications", "app", "models", "notifyd", "email", "templates", "code_scanning_alert", "#{template_name}.html.erb")

        ERB.new(File.read(html_template_file)).result(binding)
      end

      sig { returns(String) }
      def text_body
        text_template_file = Rails.root.join("packages", "notifications", "app", "models", "notifyd", "email", "templates", "code_scanning_alert", "#{template_name}.text.erb")

        ERB.new(File.read(text_template_file), trim_mode: "%<>").result(binding)
      end

      sig { returns(Notifyd::Email::FromAddress) }
      def email_from
        FromAddress.new(author: Email::AuthorUser.new(user: @actor))
      end

      sig { returns(T::Hash[String, String]) }
      def headers
        EmailHeaders.new(@subject, @subject.repository, @actor.display_login).build
      end

      sig { returns(String) }
      def template_name
        @operation.serialize
      end

      sig { returns(String) }
      def email_subject
        case @operation
        when Operations::CodeScanningAlertOperation::Assigned
          "[#{T.must(@subject.repository).name_with_display_owner}] Code scanning alert assignment (##{@subject.alert_number})"
        when Operations::CodeScanningAlertOperation::Dismissed
          "[#{T.must(@subject.repository).name_with_display_owner}] Code scanning alert dismissed (##{@subject.alert_number})"
        else
          raise ArgumentError, "Unknown operation: #{@operation}"
        end
      end
    end
  end
end
