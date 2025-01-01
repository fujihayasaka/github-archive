# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd
  module NotificationBuilders
    class GistCommentCreate
      class EmailLayoutBuilder
        extend T::Sig

        attr_reader :subject, :gist, :actor_display_login

        def initialize(subject:, gist:, actor_display_login:)
          @subject = subject
          @gist = gist
          @actor_display_login = actor_display_login
        end

        def build
          newsies_legacy_list_id = "#{gist.user} <#{gist.user}.#{gist.user}.#{GitHub.urls.host_name}>"

          headers = EmailHeaders.new(subject, gist, actor_display_login)
            .with_in_reply_to(gist.message_id)
            .with_list_id(newsies_legacy_list_id)
            .with_list_archive(gist.user.permalink)
            .build

          Notifyd::NewIntegrator::Entities::EmailBasic.new do |email|
            email.subject = "Re: #{gist.name_with_title}"
            email.body = html_body
            email.text_body = text_body
            email.url = subject.permalink
            email.unsubscribe_url_templates = Email::UnsubscribeUrlTemplates.new.to_h
            email.reasons_to_words = Syllabus::REASONS_TO_WORDS
            email.to = "#{subject.user.display_login} <#{subject.user.display_login}@noreply.#{GitHub.urls.smtp_domain}>"
            email.headers = headers

            email.use_from(name: subject.user.safe_profile_name)
          end
        end

        sig { returns(String) }
        def text_body
          "@#{subject.user.display_login} commented on this gist:\n\n#{subject.body}"
        end

        sig { returns(String) }
        def html_body
          if subject_body_email_html? || subject_body_html?
            content_html_header = "<strong>@#{subject.user.display_login}</strong> commented on this gist. <hr/>"
            "#{content_html_header}\n#{subject_body}"
          else
            # fallback to text even in the HTML part
            text_body
          end
        end

        sig { returns(T::Boolean) }
        def subject_body_email_html?
          subject.respond_to?(:body_html_for_email) && subject.body_html_for_email.present?
        end

        sig { returns(T::Boolean) }
        def subject_body_html?
          subject.respond_to?(:body_html) && subject.body_html.present?
        end

        sig { returns(String) }
        def subject_body
          if subject_body_email_html?
            subject.body_html_for_email.to_str
          elsif subject_body_html?
            subject.body_html.to_str
          else
            subject.body || ""
          end
        end
      end

      extend T::Sig
      extend Notifyd::NewIntegrator::MessageBuilder

      sig { returns(Notifyd::NewIntegrator::Event) }
      attr_reader :event

      sig { override.params(event: Notifyd::NewIntegrator::Event).returns(T.nilable(Notifyd::NewIntegrator::NotifyMessage)) }
      def self.build_message(event:)
        new(event: event).build_message
      end

      sig { params(event: Notifyd::NewIntegrator::Event).void }
      def initialize(event:)
        @event = event
      end

      sig { returns(T.nilable(Notifyd::NewIntegrator::NotifyMessage)) }
      def build_message
        subject = event.subject.type.constantize.find_by(id: event.subject.id)
        return unless subject.gist&.user&.present? # skip anonymous gists

        trigger = "create"
        explicit_recipients = Notifyd::Publishing::RecipientGroups
          .new(groups: Notifyd::RecipientsHelper.new(subject, trigger).explicit_recipients)
          .filter_for(feature_flag: GitHub.flipper[:notifyd_gist_comment_notify])
          .map do |reason_group|
            NewIntegrator::Entities::ExplicitRecipientsWithReason.new(
              reason: T.let(reason_group[:reason], String),
              recipient_ids: T.let(reason_group[:user_ids], T::Array[Integer])
            )
          end

        authzd_attributes = subject.permissions_wrapper.serialized_subject_attributes
        authzd_attributes << Authzd::Proto::Attribute.wrap("actor.spammy", subject.user&.spammy?)
        authzd_attributes << Authzd::Proto::Attribute.wrap("actor.suspended", subject.user&.suspended?)

        NewIntegrator::NotifyMessage.new(event: event) do |builder|
          builder.explicit_recipients = explicit_recipients
          builder.notification_id = subject.permalink
          builder.notification_type = NewIntegrator::NotificationType::Standard.new

          if subject.gist.user&.organization?
            builder.organization_owner_id = subject.gist.user_id
          else
            builder.user_owner_id = subject.gist.user_id
          end

          builder.authzd_attributes = authzd_attributes
          builder.email_layout = EmailLayoutBuilder.new(subject: subject, gist: subject.gist, actor_display_login: event.actor.display_login).build
          builder.trigger = trigger
          builder.push_attribute(name: "thread_participant_activity", value: "true")
          builder.push_attribute(name: "thread_type", value: "gist")
          builder.push_topic(value: subject.gist.id.to_s, type: "gist")
        end
      end
    end
  end
end
