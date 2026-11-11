# typed: strict
# frozen_string_literal: true

module Notifyd
  module Email
    class AgentSessionFinishedRenderer
      HTML_BODY_PATH = T.let(Rails.root.join("packages/notifications/app/models/notifyd/email/templates/agent_session_finished/notification.html.erb"), Pathname)
      TEXT_BODY_PATH = T.let(Rails.root.join("packages/notifications/app/models/notifyd/email/templates/agent_session_finished/notification.text.erb"), Pathname)

      sig { returns(::AgentSessionFinishedNotification) }
      attr_reader :notification

      sig { returns(User) }
      attr_reader :actor

      sig { returns(String) }
      def self.html_body_template
        @html_body_template ||= T.let(HTML_BODY_PATH.read, T.nilable(String))
      end

      sig { returns(String) }
      def self.text_body_template
        @text_body_template ||= T.let(TEXT_BODY_PATH.read, T.nilable(String))
      end

      sig do
        params(
          notification: ::AgentSessionFinishedNotification,
          actor: User,
          beacon_url: String,
        ).void
      end
      def initialize(notification:, actor:, beacon_url: "")
        @notification = notification
        @actor = actor
        @repository = T.let(T.cast(T.must(notification.repository), ::Repository), ::Repository)
        @beacon_url = T.let(beacon_url, String)
      end

      sig { returns(Notifyd::Proto::Layouts::Email::Basic) }
      def render
        from = FromAddress.new(author: AuthorRepoName.new(name: repo_name))
        reasons_explainer = ReasonsExplainer.new

        Notifyd::Proto::Layouts::Email::Basic.new(
          headers: headers,
          from: from.serialize,
          to: no_reply_address,
          subject: email_subject,
          reasons_to_words: reasons_explainer.serialize,
          body: html_body,
          text_body: text_body,
          url: notification.permalink,
          beacon_url: @beacon_url,
        )
      end

      private

      sig { returns(T::Hash[String, String]) }
      def headers
        EmailHeaders.new(notification, @repository, @actor.display_login)
          .with_in_reply_to(notification.message_id)
          .build
      end

      sig { returns(String) }
      def no_reply_address
        NoReplyAddress.new(
          name: @repository.name_with_display_owner,
          handle: T.must(@repository.owner).to_s,
        ).to_s
      end

      sig { returns(String) }
      def html_body
        ERB.new(self.class.html_body_template).result(binding)
      end

      sig { returns(String) }
      def text_body
        ERB.new(self.class.text_body_template).result(binding)
      end

      sig { returns(String) }
      def email_subject
        "[#{repo_name}] #{notification.title}"
      end

      sig { returns(String) }
      def repo_name
        @repository.name_with_display_owner
      end

      sig { returns(String) }
      def notification_settings_url
        UrlHelpers.settings_notification_preferences_url(host: GitHub.url)
      end

      sig { returns(String) }
      def survey_url
        "https://gh.io/copilot-coding-agent-survey"
      end

      # Lightweight Author implementation that uses a static name (e.g. a repo
      # name) instead of a User's profile name so the email "From" header shows
      # the repository rather than the acting user.
      class AuthorRepoName
        include Author

        sig { params(name: String).void }
        def initialize(name:)
          @name = T.let(name, String)
        end

        sig { override.returns(String) }
        def profile_name
          @name
        end
      end
    end
  end
end
