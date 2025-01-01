# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class PullRequestReviewComment < Newsies::Emails::PullRequestComment
      class Error < StandardError; end

      def self.matches?(comment)
        comment.is_a?(::PullRequestReviewComment)
      end

      sig { returns T.nilable(::PullRequest) }
      def pull_request
        T.let(comment, ::PullRequestReviewComment).pull_request
      end

      sig { returns T.nilable(::Issue) }
      def issue
        pull_request&.issue
      end

      def url
        if pull_comparison = comment.original_pull_request_comparison
          GitHub.url + pull_request_comparison_path(pull_comparison, anchor: "r#{comment.id}")
        else
          raise Error, "#{comment.class}##{comment.id} is missing objects to generate comparision"
        end
      end

      def message_id
        comment.message_id
      end

      def subject
        "Re: [#{repository.name_with_display_owner}] #{issue&.title}#{issue_subject_suffix}"
      end

      def content
        content = [comment.excerpt.to_s.gsub(/^/, "> "), "", comment.body].compact.join("\n")
      end

      def content_html
        url = "#{pull_request_url(pull_request)}##{comment_discussion_anchor(comment)}"

        ["<p>In #{link_to(comment.path, url)}:</p>",
         "<pre style='color:#555'>#{comment.excerpt_html.gsub(/^/, '&gt; ')}\n</pre>",
         comment.body_html_for_email].compact.join("\n")
      end

      private

      def pull_request_comparison_path(pull_comparison, anchor:)
        base_path = pull_request_path(pull_comparison.pull)

        path = if pull_comparison.range?
          "#{base_path}/files/#{pull_comparison.start_commit.oid}..#{pull_comparison.end_commit.oid}"
        else
          "#{base_path}/files/#{pull_comparison.end_commit.oid}"
        end

        path + "##{anchor}"
      end
    end
  end
end
