# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class PullRequestReview < Newsies::Emails::Message
      def self.matches?(comment)
        comment.is_a?(::PullRequestReview)
      end

      sig { returns T.nilable(::PullRequest) }
      def pull_request
        T.let(comment, ::PullRequestReview).pull_request
      end

      def in_reply_to
        pull_request&.message_id
      end

      def message_id
        "<#{repository.name_with_display_owner}/pull/#{pull_request&.number}/review/#{comment.id}@#{GitHub.host_name}>"
      end

      def subject
        # https://github.com/github/special-projects/issues/605#issuecomment-931449389
        # Enable new subject for newly created issue/PR, to avoid broken notification email threads.
        created_at = pull_request&.created_at || Time.current
        enable_new_title = created_at > Newsies::Emails::Message.switch_to_new_subject_from

        if enable_new_title
          "Re: [#{repository.name_with_display_owner}] #{pull_request&.title} (PR ##{pull_request&.number})"
        else
          "Re: [#{repository.name_with_display_owner}] #{pull_request&.title} (##{pull_request&.number})"
        end
      end

      def content
        body = comment.notifications_summary_title + "\n\n" + comment.body.to_s + "\n\n"
        body << comment.review_comments.map do |pr_comment|
          on_file = pr_comment&.pull_request_review_thread&.on_file?
          filename = "On #{pr_comment.path}:" if on_file
          excerpt = pr_comment.excerpt.to_s.gsub(/\A/, "> ") unless on_file
          [filename, excerpt, "", pr_comment.body].compact.join("\n")
        end.join("\n\n")
      end

      def content_html
        body = "<p><b>@#{comment.user.display_login}</b> #{comment.state_summary} this pull request.</p>\n\n"
        body << comment.body_html_for_email if comment.body
        body << comment.review_comments.map do |pr_comment|
          on_file = pr_comment&.pull_request_review_thread&.on_file?
          preposition = on_file ? "On" : "In"
          excerpt = "<pre style='color:#555'>#{pr_comment.excerpt_html.gsub(/\A/, '&gt; ')}\n</pre>" unless on_file
          ["<hr>\n\n<p>#{preposition} #{link_to(pr_comment.path, pr_comment.permalink)}:</p>",
            excerpt,
            pr_comment.body_html_for_email].compact.join("\n")
        end.join("\n\n")
      end

      def url
        comment.notifications_permalink
      end

      def entity
        repository
      end
    end
  end
end
