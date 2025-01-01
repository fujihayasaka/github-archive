# typed: strict
# frozen_string_literal: true

module Notifyd
  module Email
    class IssueCommentRenderer
      Layouts = Notifyd::Proto::Layouts::Email

      sig { params(comment: ::IssueComment, issue: ::Issue, author: Author, context: T.nilable(Context)).void }
      def initialize(comment:, issue:, author:, context: nil)
        @comment = comment
        @issue = issue
        @author = author
        @context = T.let(context || {}, Context)
      end

      sig { returns(Layouts::Basic) }
      def render
        repository = issue.repository
        subject = IssueSubject.new(issue: issue, repository: repository)
        from = FromAddress.new(author: author)
        reasons_explainer = ReasonsExplainer.new
        headers = EmailHeaders.new(comment, repository, context[:actor_login])
          .with_in_reply_to(issue.message_id)

        if FeatureFlag.vexi.enabled?(:additional_issue_email_headers, author.user, default: false)
          is_pr = issue.pull_request?

          headers = headers.with_labels(issue.labels)
            .with_milestone(issue.milestone)
            .with_assignees(issue.assignees)
            .with_issue_type(issue.issue_type)
            .with_issue_state(is_pr ? nil : issue.state)
            .with_pull_request_status(is_pr ? issue.pull_request&.state&.to_s : nil)
        end

        headers = headers.build
        to = repository.present? ? NoReplyAddress.new(name: repository.name_with_display_owner, handle: repository.to_s || "") : ""
        unsubscribe_url_templates = UnsubscribeUrlTemplates.new

        Layouts::Basic.new(
          body: comment.body_html_for_email&.to_str,
          from: from.serialize,
          headers: headers,
          reasons_to_words: reasons_explainer.serialize,
          subject: "Re: #{subject.serialize}",
          text_body: comment.body,
          to: to.to_s,
          unsubscribe_url_templates: unsubscribe_url_templates.serialize,
          url: comment.permalink,
        )
      end

      private

      sig { returns(::IssueComment) }
      attr_reader :comment
      sig { returns(::Issue) }
      attr_reader :issue
      sig { returns(Author) }
      attr_reader :author
      sig { returns(Context) }
      attr_reader :context
    end
  end
end
