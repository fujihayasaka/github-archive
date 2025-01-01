# typed: strict
# frozen_string_literal: true

module Notifyd
  module Email
    class MemexProjectStatusRenderer

      HTML_BODY_PATH = T.let(Rails.root.join("packages/notifications/app/models/notifyd/email/templates/memex_project_status/notification.html.erb"), Pathname)
      TEXT_BODY_PATH = T.let(Rails.root.join("packages/notifications/app/models/notifyd/email/templates/memex_project_status/notification.text.erb"), Pathname)

      sig { returns(MemexProjectStatus) }
      attr_reader :memex_project_status

      sig { returns(Author) }
      attr_reader :author

      sig { returns(MemexProject) }
      attr_reader :memex_project

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
          memex_project_status: MemexProjectStatus,
          author: Author,
          actor: User,
        ).void
      end
      def initialize(memex_project_status:, author:, actor:)
        @author = author
        @memex_project_status = memex_project_status
        @memex_project = T.let(T.must(@memex_project_status.memex_project), MemexProject)
        @actor = actor
      end

      sig { returns(Notifyd::Proto::Layouts::Email::Basic) }
      def render
        from = FromAddress.new(author: @author)

        Notifyd::Proto::Layouts::Email::Basic.new(
          headers: headers,
          from: from.serialize,
          to: no_reply_address,
          subject: email_subject,
          body: html_body,
          text_body: text_body,
          url: memex_project_status.permalink,
        )
      end

      private

      sig { returns(T::Hash[String, String]) }
      def headers
        EmailHeaders.new(memex_project_status, memex_project, actor.display_login)
          .with_list_id(memex_project.list_id)
          .with_in_reply_to(memex_project_status.message_id)
          .build
      end

      # The "To" header contains the email address of the MemexProject, the recipient will appear in the "CC" list.
      sig { returns(String) }
      def no_reply_address
        NoReplyAddress.new(
          name: memex_project.title,
          handle: memex_project.owner.to_s,
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

      sig { returns(Notifyd::EmailHeaders) }
      def email_headers
        EmailHeaders.new(
          memex_project_status,
          memex_project,
          actor.display_login,
        )
      end

      sig { returns(String) }
      def email_subject
        "[#{memex_project.owner.display_login}] #{memex_project.title} (Project ##{memex_project.number}) Status update"
      end
    end
  end
end
