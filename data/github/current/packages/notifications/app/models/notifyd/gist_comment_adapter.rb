# typed: true
# frozen_string_literal: true

module Notifyd
  class GistCommentAdapter < SubjectAdapter
    prepend SubjectAdapterTracer

    Layouts = Notifyd::Proto::Layouts::Email

    def matches?
      return false unless subject.gist&.user&.present?
      true
    end

    def notify_feature_flag
      GitHub.flipper[:notifyd_gist_comment_notify]
    end

    def notification_id
      subject.permalink
    end

    def authzd_attributes
      attributes = subject.permissions_wrapper.serialized_subject_attributes
      attributes << Authzd::Proto::Attribute.wrap("actor.spammy", actor&.spammy?)
      attributes << Authzd::Proto::Attribute.wrap("actor.suspended", actor&.suspended?)
    end

    def actor
      @actor ||= User.find_by(id: context[:actor_id])
    end

    def saml_enforcement
      owner&.organization? ? { organization_id: owner.id } : { skip_enforcement: true }
    end

    # we don't have support for Gists in GitHub App
    def mobile_layout
    end

    def email_layout
      newsies_legacy_list_id = "#{subject.gist.user} <#{subject.gist.user}.#{subject.gist.user}.#{GitHub.urls.host_name}>"

      headers = EmailHeaders.new(subject, gist, context[:actor_login])
        .with_in_reply_to(gist.message_id)
        .with_list_id(newsies_legacy_list_id)
        .with_list_archive(subject.gist.user.permalink)
        .build

      Layouts::Basic.new(
        subject: "Re: #{gist.name_with_title}",
        body: gist_comment_html_mail_body,
        text_body: gist_comment_text_mail_body,
        from: Layouts::From.new(name: subject.user.safe_profile_name),
        url: subject.permalink,
        unsubscribe_url_templates: Email::UnsubscribeUrlTemplates.new.serialize,
        reasons_to_words: email_reasons_to_words,
        to: "#{subject.user.display_login} <#{subject.user.display_login}@noreply.#{GitHub.urls.smtp_domain}>",
        headers: headers
      )
    end

    def gist_comment_html_mail_body
      if subject_body_email_html? || subject_body_html?
        content_html_header = "<strong>@#{subject.user.display_login}</strong> commented on this gist. <hr/>"
        "#{content_html_header}\n#{subject_body}"
      else
        # fallback to text even in the HTML part
        gist_comment_text_mail_body
      end
    end

    def gist_comment_text_mail_body
      "@#{subject.user.display_login} commented on this gist:\n\n#{@subject.body}"
    end

    def related_topics
      [
        { type: "gist", value: gist.id.to_s },
      ]
    end

    def explicit_recipients
      Notifyd::RecipientsHelper.new(
        subject,
        context[:operation],
        context[:previous_body],
        context[:current_body],
      ).explicit_recipients
    end

    def attributes
      result = []
      result << { name: "thread_type", value: "gist" }
      if trigger == "create"
        result << { name: "thread_participant_activity", value: "true" }
      end
      result.sort_by { |a| a[:name] }
    end

    def owner_id
      owner.id
    end

    def gist
      subject.gist
    end

    def owner
      gist.user
    end

    def owner_type
      owner&.organization? ? :organization : :user
    end

    def trigger
      context[:operation]
    end

    def repository_id
      nil
    end
  end
end
