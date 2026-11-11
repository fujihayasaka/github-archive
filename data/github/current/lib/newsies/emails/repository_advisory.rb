# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class RepositoryAdvisory < Newsies::Emails::Message
      def self.matches?(comment)
        comment.is_a?(::RepositoryAdvisory)
      end

      sig { returns ::RepositoryAdvisory }
      def repository_advisory
        comment
      end

      def subject
        "[#{repository.name_with_display_owner}] #{title} (#{repository_advisory.ghsa_id})"
      end

      def body
        :repository_advisory
      end

      def body_html
        :repository_advisory_html
      end

      def entity
        repository
      end

      def title
        repository_advisory.get_title(user)
      end

      def description
        repository_advisory.markdown_description
      end

      def permalink
        return repository_advisory.permalink unless newsies_email_click_tracking_enabled?

        add_tracking_params(repository_advisory.permalink, "repo_advisory_click")
      end

      # Only administrators get this initial email.
      def reason_in_words
        "You are receiving this because you are an administrator on #{repository.name_with_display_owner}."
      end

      # Copied from Message.
      # Right now, you can't unsubcribe and clicking the unsub link causes
      # an error!, so we deleted the unsubscribe link from the orig method.
      def footer_html
        # Using a unicode `—` messes with the  encoding of the resulting message.
        msg = [MDASH, tag("br"), reason_in_words, tag("br")]

        if replyable?
          msg << "Reply to this email directly, or "
          msg << link_to("view it on #{GitHub.flavor}", footer_url_with_tracking_params) << "."
        else
          msg << link_to("View it on #{GitHub.flavor}", footer_url_with_tracking_params) << "."
        end

        msg = safe_join(msg)
        msg += mark_read_image if tracking_image_enabled?

        content_tag(:p, msg, style: "font-size:small;-webkit-text-size-adjust:none;color:#666;")
      end
    end
  end
end
