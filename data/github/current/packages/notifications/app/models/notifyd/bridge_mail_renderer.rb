# typed: true
# frozen_string_literal: true

module Notifyd
  # This class tries to render the body of a mail from Newsies using the minimum data needed.
  # It also removes the tracking image used to mark notifications as read because they need
  # extra work from the Newsies system that we don't want to use.
  #
  # For the actual mail build step @see Notifyd::BridgeMailer
  class BridgeMailRenderer
    module Untrack
      # Don't render the tracking image. This requires DB objects like
      # NotificationSummary and we don't want to create/update it from here.
      def tracking_image_enabled?
        false
      end
    end

    # The smallest version of Newsies::Delivery needed for rendering
    class SmallDelivery < T::Struct
      prop :comment, T.any(ActiveRecord::Base, Object)

      def comment_id
        Newsies::Comment.to_id(comment)
      end

      def comment_type
        Newsies::Comment.to_type(comment)
      end
    end

    # The smallest version of Newsies::Settings needed for rendering
    SmallSettings = Struct.new(:user)

    class Part
      attr_reader :headers, :content

      # Convert Mail::Part into our internal Part object
      def self.from_mail(mail_part)
        # Calling #ready_to_send! will make sure that the part has all the headers set,
        # like Content-Transfer-Encoding
        mail_part.ready_to_send!

        headers = {
          "Content-Type" => mail_part.content_type,
          "Content-Transfer-Encoding" => mail_part.content_transfer_encoding,
        }

        # This ensures that the content is properly encoded with the defined Content-Transfer-Encoding
        content = mail_part.body.encoded(mail_part.content_transfer_encoding)

        new(headers.compact, content)
      end

      def initialize(headers, content)
        @headers = headers
        @content = content
      end

      def to_h
        { headers: headers, content: content }
      end
    end

    attr_reader :subject, :user, :comment, :message_class

    # To render a Newsies mail we need
    #
    # subject - The mail subject or title, used in parts of the body
    # user - Who is this sent to
    # comment - Newsies works around the concept of comments, wrapper classes around the models that initiate a notification.
    #   For example for a CheckSuite model this would be: ::CheckSuiteEventNotification.new(check_suite)
    # message_class - Newsies class used to build the body of the message, for example Newsies::Mailers::CheckSuiteEventNotification
    def initialize(subject:, user:, comment:, message_class:)
      @subject = subject
      @user = user
      @comment = comment
      @message_class = message_class
    end

    def parts
      @parts ||= [text_part, html_part]
    end

    def text_part
      @text_part ||= Part.from_mail(mail.text_part)
    end

    def html_part
      @html_part ||= Part.from_mail(mail.html_part)
    end

    def mail
      @mail ||= build_mail
    end

    private

    def build_mail
      delivery = SmallDelivery.new(comment: comment)
      settings = SmallSettings.new(user)
      message = message_class.new(delivery, settings, {})
      # Extend the message class so it doesn't include tracking
      message.extend Untrack

      BridgeMailer.with(subject: subject, message: message).build_mail
    end
  end
end
