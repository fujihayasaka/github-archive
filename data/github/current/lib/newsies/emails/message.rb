# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class Message
      include ::ApplicationMailer::Helpers
      include ::ActionView::Helpers::UrlHelper
      include ::ActionView::Helpers::TagHelper
      include ::ActionView::Helpers::AssetTagHelper
      include UrlHelper
      include EscapeHelper

      # https://github.com/github/special-projects/issues/605#issuecomment-934217213
      # Dotcom: Just selected date as of October 17th 2021 , after which any newly created issue/PR will have new subject.
      # Else the old one, which does not specify in subject like (Issue XXX) or (PR XXX)
      SWITCH_TO_NEW_SUBJECT_FROM = ActiveSupport::TimeZone["Pacific Time (US & Canada)"].local(2021, 10, 17)

      # Public: Determine if this message can be used for the given comment.
      #
      # comment - An object that will be used to construct the message
      #
      # Returns a boolean.
      sig { params(comment: T.untyped).returns(T::Boolean) }
      def self.matches?(comment)
        false
      end

      # Public: Determine switch over date to enable new subject in email.
      sig { returns ActiveSupport::TimeWithZone }
      def self.switch_to_new_subject_from
        return SWITCH_TO_NEW_SUBJECT_FROM unless GitHub.enterprise?
        # Enable new subject for newly created issue/PR on GHES 3.4 or greater.
        value = Notifications::KV.store.get("switch_to_new_subject_from")
        return ActiveSupport::TimeZone["Pacific Time (US & Canada)"].parse(value.value!) if value.ok? && value.value!

        value = ActiveSupport::TimeZone["Pacific Time (US & Canada)"].now
        ActiveRecord::Base.connected_to(role: :writing) do
          Notifications::KV.store.set("switch_to_new_subject_from", value.to_s)
        end

        value
      end

      delegate :comment, to: :@delivery

      sig { returns T.nilable(T.any(Newsies::Settings, Notifyd::BridgeMailRenderer::SmallSettings)) }
      attr_accessor :settings

      # Initialize a new email message
      #
      # delivery - a Newsies::Delivery object
      # settings - An instance of Newsies::Settings
      # options  - A Hash with message-specific options
      #            :reason - Symbol reason for sending the email:
      #              :mention, :team_mention, :assign, :author, nil
      sig do
        params(
          delivery: T.nilable(T.any(Newsies::Delivery, Notifyd::BridgeMailRenderer::SmallDelivery)),
          settings: T.nilable(T.any(Newsies::Settings, Notifyd::BridgeMailRenderer::SmallSettings)),
          options: T.nilable(Hash)
        ).void
      end
      def initialize(delivery, settings, options = nil)
        @delivery = delivery
        @settings = settings
        @options = options || {}
        @tokenized_list_address = @recipient_email = nil
      end

      sig { returns T.nilable(T::Boolean) }
      def deliverable?
        @settings && @delivery && can_send_to_email?
      end

      def undeliverable_reason
        @undeliverable_reason
      end

      sig { returns T::Boolean }
      def can_send_to_email?
        return false if recipient_email.blank?
        return true if !GitHub.email_verification_enabled?
        settings_user = self.settings_user
        if settings_user
          return true if settings_user.is_enterprise_managed?
          return true if settings_user.emails.verified.exists?(email: recipient_email)
        end
        GitHub.dogstats.increment("newsies.delivery.blocked_emails")
        false
      end

      sig { returns T.nilable(T::Boolean) }
      def replyable?
        GitHub.email_replies_enabled? && tokenized_list_address != GitHub.urls.noreply_address
      end

      # Public: Gets the GitHub user that created the comment that triggered
      # this notification.
      def sender
        @sender ||= comment.notifications_author
      end

      # Public: Email address of the user that's sending the message.
      #
      # Returns a String email address in "full name <address>" format.
      sig { returns String }
      def sender_address
        if GitHub.email_replies_enabled? && !GitHub.mail_use_noreply_addr
          user_email sender, GitHub.urls.notifications_sender_address
        else
          user_email sender, GitHub.urls.noreply_address
        end
      end

      # Public: Email address of the user that will receive this message. Note
      # that this isn't necessary the address used in the To header. It may be
      # placed on the Cc or the Bcc depending on whether the user was mentioned,
      # created, or is assigned to the thread.
      sig { returns String }
      def recipient_address
        user_email settings_user, recipient_email
      end

      sig { returns T.nilable(String) }
      def recipient_login
        settings_user&.display_login
      end

      # Like recipient_address but only the email address portion, no name.
      sig { returns T.nilable(String) }
      def recipient_email
        if entity.respond_to?(:organization)
          @recipient_email ||= org_email_address
        elsif @settings&.is_a?(Newsies::Settings)
          @recipient_email ||= @settings.email(:global).address
        end
      end

      # Public: A constructed email address that identifies the reason an email
      # was received. This is used as a cc address which can be useful for filtering.
      sig { returns T.nilable(String) }
      def reason_email_address
        if reason.present?
          reason_email_address = quote_email_address("#{reason}@noreply.#{GitHub.urls.smtp_domain}")
          %{"#{reason.capitalize.tr('_-', ' ')}" #{reason_email_address}}
        end
      end

      # Public: Email address of the project distribution list. This is
      # typically of the form: "reply+TOKEN@reply.github.com".
      #
      # The tokenized_list_address must be used as the Reply-To address in
      # order to properly route mail replies.
      #
      # Returns a String email address.
      sig { returns String }
      def tokenized_list_address
        @tokenized_list_address ||=
          GitHub::Email.reply_email(comment, settings_user)
      end

      # Public: Email address of the email addressed used to unsubscribe from
      # the list.
      #
      # Returns a String email address.
      sig { returns String }
      def tokenized_unsubscribe_address
        GitHub::Email.unsub_email(comment, settings_user)
      end

      sig { returns String }
      def tokenized_unsubscribe_auth_url
        user = settings_user
        token = Newsies::Authentication.token(
          :mute_auth,
          user,
          delivery_summary_id,
          { thread_key: Thread.to_object(@delivery&.comment).key }
        )

        "#{GitHub.url}/notifications/unsubscribe-auth/#{token}"
      end

      sig { returns String }
      def unsubscribe_vuln_url
        token = Newsies::Authentication.token :mute_vuln, settings_user, delivery_summary_id
        "#{GitHub.url}/notifications/unsubscribe-vulnerability/#{token}"
      end

      sig { returns String }
      def unsubscribe_dependabot_notifications_url
        token = Newsies::Authentication.token :unsubscribe_vulnerability_alerts, settings_user, delivery_summary_id

        "#{GitHub.url}/notifications/unsubscribe/dependabot-alerts/new-vulnerabilities/#{token}"
      end

      sig { returns String }
      def tokenized_unsubscribe_list_url
        token = Newsies::Authentication.token :mute_list, settings_user, delivery_summary_id

        "#{GitHub.url}/notifications/unsubscribe/one-click/#{token}"
      end

      # Public: Email address of the project distribution list used in
      # no-reply situations.
      #
      # Returns a String email address in "full name <address>" format.
      sig { returns String }
      def noreply_list_address
        if GitHub.email_replies_enabled? && !GitHub.mail_use_noreply_addr
          notifications_list_email(notifications_list, "#{notifications_list.name}@noreply.#{GitHub.urls.smtp_domain}")
        else
          notifications_list_email(notifications_list, GitHub.urls.noreply_address)
        end
      end

      # Public: Email address used in the From field of the mail message. This
      # header is important because the "show images from this user" feature
      # depends on it not changing.
      sig { returns String }
      def from
        sender_address
      end

      # Public: Array of actual email addresses to deliver the message to. The
      # To, Cc, and Bcc have no bearing on where the message is actually
      # delivered when this returns a non-nil value. The addresses listed here
      # are not included in the mail message, rather they are provided to the
      # SMTP server on the RCPT TO line.
      sig { returns T::Array[String] }
      def destinations
        [recipient_email].compact
      end

      # Public: Email address used in the To field of the message. This is
      # not the recipient as you might first suspect but is instead set to the
      # notifications_list's distribution list.
      #
      # Returns a String email address in "full name <address>" format.
      sig { returns String }
      def to
        noreply_list_address
      end

      # Public: Email address used in the Reply-To field of the mail message.
      # This is set to the tokened list address by default to emulate a
      # mailing list.
      #
      # Returns a String email address in "full name <address>" format.
      sig { returns String }
      def reply_to
        notifications_list_email(notifications_list, tokenized_list_address)
      end

      # Public: Email address used in the Bcc field of the mail message.
      # This is set to the recipient's configured email address. This field is
      # mostly worthless since #destinations controls where the message is
      # delivered.
      #
      # Returns a String email address in "full name <address>" format.
      sig { returns T.nilable(String) }
      def bcc
      end

      # Public: Email address used in the Cc field of the mail message.
      # This is set to the recipient's configured email address sometimes.
      #
      # Returns a String email address in "full name <address>" format.
      sig { returns T.nilable(String) }
      def cc
        if participating?
          recipient_address
        end
      end

      # Public: Email addresses used in the Cc field of the mail message.
      #
      # Returns an array of email addresses.
      sig { returns T::Array[String] }
      def cc_list
        [cc, reason_email_address].compact
      end

      # Public: The subject of this message. Subclasses should override this
      # method with a subject appropriate for the message type.
      def subject
        raise ArgumentError, "No subject provided by #{self.class}"
      end

      # Public: The Message-Id to use in outgoing email notifications. This
      # should follow RFC 2822's definition of message-id fields:
      #
      # http://tools.ietf.org/html/rfc2822#section-3.6.4
      def message_id
        comment.message_id
      end

      # Public: The message ID that this message is replying to.
      def in_reply_to
      end

      sig { returns String }
      def list_id
        address = "<#{notifications_list}.#{notifications_list.owner&.display_login}.#{GitHub.urls.host_name}>"
        "#{notifications_list.name_with_display_owner} #{address}"
      end

      sig { returns String }
      def list_post_address
        tokenized_list_address
      end

      def unsubscribe_list
        if email = tokenized_unsubscribe_address
          %(<mailto:#{email}>, <#{tokenized_unsubscribe_list_url}>)
        end
      end

      # Public: Should the 1x1 tracking image be inserted into the message?
      # Defaults to true. Subclasses may override this setting to disable the
      # tracking image.
      sig { returns T::Boolean }
      def tracking_image_enabled?
        true
      end

      # Public: Permalink to the item that this message is for.
      sig { returns String }
      def url
        comment.permalink
      end

      # Public: Headers to include in outgoing email related to this
      # notification. Subclasses may override this to include additional
      # values.
      #
      # Returns a Hash of header names and values.
      sig { returns T::Hash[String, T.untyped] }
      def headers
        @headers ||= begin
          {
            "Message-Id" => message_id,
            "In-Reply-To" => in_reply_to,
            "References" => in_reply_to,
            "Precedence" => "list",
            "Return-Path" => "<#{GitHub.urls.noreply_address}>",
            "X-GitHub-Sender" => sender&.display_login,
            "X-GitHub-Recipient" => recipient_login,
            "X-GitHub-Reason" => reason,
            "List-ID" => list_id,
            "List-Archive" => notifications_list.permalink,
            "List-Post" => "<mailto:#{list_post_address}>",
            "List-Unsubscribe" => unsubscribe_list,
          }.delete_if { |_k, v| v.blank? }.tap do |h|
            if h["List-Unsubscribe"].present?
              h["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
            end
          end
        end
      end

      # The message's body parts.
      #
      # Returns an array of [type, body] tuples. The body can either be a
      # string of the whole body or a symbol matching one of the template
      # in the app/views/mailer/newsies directory.
      sig { returns T::Array[[String, String]] }
      def parts
        res = []
        res << ["text/plain", body]
        res << ["text/html", body_html] if body_html?
        res
      end

      sig { returns String }
      def body
        [content, footer].join("\n\n")
      end

      # Internal: The content for this notification.
      sig { returns T.nilable(String) }
      def content
        comment.body
      end

      # Internal: The reason this notification is being emailed as a sentence.
      sig { returns String }
      def reason_in_words
        "You are receiving this because #{GitHub.newsies.reason_in_words(reason, email: true)}."
      end

      # Internal: The reason this notification is being emailed.
      sig { returns String }
      def reason
        @options[:reason].to_s
      end

      # Internal: The content header for this notification if any.
      #
      # Useful to clarify user actions like "@user commented on" and prevent phishing attacks.
      sig { returns T.nilable(String) }
      def content_header
      end

      # Internal: The content header for this notification if any.
      #
      # Useful to clarify user actions like "@user commented on" and prevent phishing attacks.
      sig { params(action_text: String).returns(String) }
      def content_header_plain(action_text:)
        "#{sender&.display_login} #{action_text} (#{repository.name_with_display_owner}##{T.must(issue).number})"
      end

      # Internal: The content header with avatar for this notification if any.
      #
      # Useful to clarify user actions like "@user commented on" and prevent phishing attacks.
      sig { params(action_text: String, hidden: T::Boolean).returns(String) }
      def content_header_with_avatar(action_text:, hidden: false)
        if GitHub.flipper[:newsies_remove_alt_from_email_avatar].enabled?(settings_user)
          avatar_html = image_tag(comment.user.primary_avatar_url(20), height: 20, width: 20, style: "border-radius:50%; margin-right: 4px;", decoding: "async")
        else
          avatar_html = image_tag(comment.user.primary_avatar_url(20), alt: comment.user.display_login, height: 20, width: 20, style: "border-radius:50%; margin-right: 4px;", decoding: "async")
        end
        inner_html = avatar_html + content_tag(:strong, "#{sender&.display_login}") + " #{action_text} " + link_to("(#{repository.name_with_display_owner}##{T.must(issue).number})", url)
        content_tag(:div, inner_html, style: "display: flex; flex-wrap: wrap; white-space: pre-wrap; align-items: center; #{hidden ? 'visibility: hidden;' : ''}")
      end

      # Internal: The footer for this notification.
      #
      # Note that the space is intentional to match RFC expectations.
      sig { returns String }
      def footer
        actionable = if replyable?
          "Reply to this email directly or view it on #{GitHub.flavor}:\n#{url}"
        else
          "View it on #{GitHub.flavor}:\n#{url}"
        end
        # Add the unique message ID to prevent email clients from hiding the footer
        # https://github.com/github/special-projects/issues/578
        "-- \n#{actionable}\n#{reason_in_words}\n\nMessage ID: #{message_id}"
      end

      # Check that the Message supports HTML email bodies. By default, this is
      # enabled for comment objects that respond to :body_html (all user
      # content on github). Message subclasses may also override this and the
      # body_html method to provide a custom implementation.
      #
      # Returns true when this message supports generating an HTML email body.
      sig { returns T::Boolean }
      def body_html?
        comment.respond_to?(:body_html)
      end

      # The body HTML used in email notification messages. By default, these include
      # the #body_html and #url in a signature area.
      #
      # Returns the email body as a String of simple HTML markup.
      sig { returns String }
      def body_html
        html = [content_header_html, content_html, "", footer_html]
        html << json_ld_html

        html.join "\n"
      end

      # The content header HTML
      sig { returns String }
      def content_header_html
        content_tag(:p, content_header)
      end

      # The body HTML without any footer.
      sig { returns T.nilable(String) }
      def content_html
        if comment.respond_to?(:body_html_for_email)
          comment.body_html_for_email
        else
          comment.body_html
        end
      end

      # The signature portion of body_html.
      MDASH = GitHub::HTMLSafeString.make("&mdash;")

      sig { returns String }
      def footer_html
        # Using a unicode `—` messes with the encoding of the resulting message.
        msg = [MDASH, tag("br")]

        if replyable?
          msg << "Reply to this email directly, "
          msg << link_to("view it on #{GitHub.flavor}", url) << ", or "
        else
          msg << link_to("View it on #{GitHub.flavor}", url) << " or "
        end

        msg << link_to("unsubscribe", tokenized_unsubscribe_auth_url) << "."
        msg = safe_join(msg)

        msg += mobile_promo_html if show_mobile_promo?

        msg += safe_join([tag("br"), reason_in_words])
        msg += mark_read_image if tracking_image_enabled?

        # Add the unique message ID to prevent email clients from hiding the footer
        invisible_styles = [
          "color: transparent",
          "font-size: 0",
          "display: none",
          "visibility: hidden",
          "overflow: hidden",
          "opacity: 0",
          "width: 0",
          "height: 0",
          "max-width: 0",
          "max-height: 0",
          "mso-hide: all"
        ].join("; ")
        unique_trailer = content_tag(:span, style: invisible_styles) do
          safe_join(["Message ID: "].concat(
            # Wrap some select characters to prevent mail clients from linkifying
            message_id.split(/([@.:])/).map { |part| content_tag(:span, part) }
          ))
        end
        # No line breaks are necessary before it since it is hidden
        msg += safe_join([unique_trailer])

        content_tag(:p, msg, style: "font-size:small;-webkit-text-size-adjust:none;color:#666;")
      end

      # A Gmail proprietary tag, which inserts a "View on GitHub" link on the
      # thread in the inbox.
      #
      # https://developers.google.com/gmail/actions/reference/go-to-action#view_action
      #
      # Returns a hash.
      sig { returns T::Hash[T.any(String, Symbol), String] }
      def gmail_view_action
        {
          "@context": "http://schema.org",
          "@type": "EmailMessage",
          potentialAction: {
            "@type": "ViewAction",
            target: url,
            url: url,
            name: "View #{conversation_type}",
          },
          description: "View this #{conversation_type} on #{GitHub.flavor}",
          "publisher": {
            "@type": "Organization",
            name: "GitHub",
            url: "https://github.com",
          },
        }
      end

      # create the script for the JSON-LD data for Gmail
      sig { returns String }
      def json_ld_html
        schemas = [gmail_view_action]
        content_tag(:script, json_escape(outlook_to_json(schemas)), { type: "application/ld+json" }, false)
      end

      def outlook_to_json(hash)
        JSON.generate(hash, {
          space: " ",
          object_nl: "\n",
          array_nl: "\n",
        })
      end

      # Public: User-facing conversation type. For example: "Pull Request",
      # or "Issue".
      #
      # Returns a String name.
      sig { returns String }
      def conversation_type
        if comment.notifications_thread.try(:pull_request?)
          "Pull Request"
        else
          comment.notifications_thread.class.name.titleize
        end
      end

      sig { returns String }
      def mark_read_image
        tag(:img, src: mark_read_url, height: 1, width: 1, alt: "")
      end

      sig { returns String }
      def mark_read_url
        token = Newsies::Authentication.token(
          :beacon,
          settings_user,
          delivery_summary_id,
          { comment_type: @delivery&.comment_type, comment_id: @delivery&.comment_id },
        )

        "#{GitHub.url}/notifications/beacon/#{token}.gif"
      end

      # Tacked at the end of Issues-related notifications.
      sig { returns String }
      def issue_subject_suffix
        issue = self.issue
        # https://github.com/github/special-projects/issues/605
        return "" unless issue.present?

        recipient = settings_user
        # https://github.com/github/special-projects/issues/605#issuecomment-931449389
        # Enable new subject for newly created issue/PR, to avoid broken notification email threads.
        issue_creation_time = issue.created_at
        enable_new_title_when = issue_creation_time && issue_creation_time > self.class.switch_to_new_subject_from
        enable_new_title = recipient && enable_new_title_when

        return " (##{issue.number})" unless enable_new_title

        if issue.pull_request?
          " (PR ##{issue.number})"
        else
          " (Issue ##{issue.number})"
        end
      end

      # Public: Should this email be blocked from being delivered because
      # the user does not meet the notification restriction requirements for
      # an organization?
      #
      # Returns a Boolean.
      sig { returns T::Boolean }
      def blocked_by_organization_restriction?
        owner = notifications_list.owner

        owner.organization? && !owner.user_can_receive_email_notifications?(settings_user)
      end

      # Public: Controls whether to enable the Primer layout to HTML emails
      #
      # Returns a Boolean.
      sig { returns T::Boolean }
      def primer_html_template_enabled?
        false
      end

      sig { returns Symbol }
      def primer_layout
        :primer_layout
      end

      protected

      sig { returns T.nilable(User) }
      def settings_user
        settings&.user
      end

      private

      # Private:  Subclasses should override this method to return an issue
      # if one is needed to construct the email.
      sig { returns T.nilable(::Issue) }
      def issue
      end

      # Private: Returns the email address for the given user and logs if there are differences
      def org_email_address
        return unless @settings
        return if @settings.is_a?(Notifyd::BridgeMailRenderer::SmallSettings)
        @settings.email(entity.organization || :global).address
      end

      # Internal method required in order to pass a block to content_tag
      #
      # &block - A block that returns a String.
      #
      # Returns the String that was returned by the block.
      def capture
        yield if block_given?
      end

      # Private: Checks if this message is being sent to someone who was participating
      # Depends on the specified reason in the message @options
      sig { returns T::Boolean }
      def participating?
        ::Newsies::Reasons::Participating.include?(@options[:reason])
      end

      def notifications_list
        comment.notifications_list
      end
      alias_method :repository, :notifications_list

      def entity
        comment.entity
      end

      sig { returns T::Boolean }
      def show_mobile_promo?
        settings_user && GitHub.flipper[:mobile_notification_emails_promo].enabled?(settings_user) &&
          !T.must(settings_user).uses_mobile_app?
      end

      sig { returns String }
      def mobile_promo_html
        safe_join([
          tag("br"),
          "Triage notifications on the go with GitHub Mobile for ",
          link_to("iOS", ios_mobile_app_store_url(campaign: "notification-email")),
          " or ",
          link_to("Android", android_mobile_app_store_url(campaign: "notification-email", medium: "email")),
          ".\n"
        ])
      end

      sig { returns T.nilable(Integer) }
      def delivery_summary_id
        return unless @delivery
        return if @delivery.is_a?(Notifyd::BridgeMailRenderer::SmallDelivery)
        @delivery.summary[:id]
      end
    end
  end
end
