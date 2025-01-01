# typed: strict
# frozen_string_literal: true

module Notifyd
  module Email
    class IssueRenderer
      Layouts = Notifyd::Proto::Layouts::Email

      class EventProxy

        sig { returns(String) }
        attr_reader :body
        alias_method :body_html_for_email, :body

        sig { params(body: String).void }
        def initialize(body)
          @body = body
        end
      end

      class EventBody

        sig { params(operation: Operations::IssueOperation, context: Context).void }
        def initialize(operation:, context:)
          @operation = operation
          @context = context
        end

        sig { returns(T.nilable(String)) }
        def html
          event&.body_html_for_email&.to_str
        end

        sig { returns(T.nilable(String)) }
        def text
          event&.body&.to_str # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end

        private

        sig { returns(Operations::IssueOperation) }
        attr_reader :operation
        sig { returns(Context) }
        attr_reader :context

        sig { returns(T.nilable(T.any(EventProxy, ::IssueEventNotification))) }
        def event
          @event ||= T.let(build_event, T.nilable(T.any(EventProxy, ::IssueEventNotification)))
        end

        sig { returns(T.nilable(T.any(EventProxy, ::IssueEventNotification))) }
        def build_event
          case operation
          when Operations::IssueOperation::Labeled
            EventProxy.new("Issue was assigned label: #{Label.find_by(id: context[:added_label_id])&.name}")
          when Operations::IssueOperation::Unlabeled
            EventProxy.new("Issue was unassigned label: #{Label.find_by(id: context[:removed_label_id])&.name}")
          when Operations::IssueOperation::Assigned,
            Operations::IssueOperation::Closed,
            Operations::IssueOperation::Reopened,
            Operations::IssueOperation::ConvertedToDiscussion
            event_id = @context[:event_id]
            IssueEventNotification.find(event_id) if event_id
          else
            nil
          end
        end
      end

      class IssueBody

        sig { params(issue: ::Issue).void }
        def initialize(issue:)
          @issue = issue
        end

        sig { returns(T.nilable(String)) }
        def html
          issue.body_html_for_email&.to_str
        end

        sig { returns(T.nilable(String)) }
        def text
          issue.body
        end

        private

        sig { returns(::Issue) }
        attr_reader :issue
      end

      Body = T.type_alias { T.any(IssueBody, EventBody) }

      sig { params(issue: ::Issue, author: Author, operation: Operations::IssueOperation, context: T.nilable(Context)).void }
      def initialize(issue:, author:, operation:, context: nil)
        @issue = issue
        @author = author
        @operation = operation
        @context = T.let(context || {}, Context)
      end

      sig { returns(T::Hash[String, String]) }
      def headers
        repository = issue.repository

        case operation
        when Operations::IssueOperation::Closed,
          Operations::IssueOperation::Reopened,
          Operations::IssueOperation::ConvertedToDiscussion
          event_id = @context[:event_id]
          subject = IssueEventNotification.find(event_id) if event_id
        else
          subject = issue
        end

        if subject.nil?
          subject = issue
        end

        headers = EmailHeaders.new(subject, repository, context[:actor_login])

        case operation
        when Operations::IssueOperation::Closed,
          Operations::IssueOperation::Reopened,
          Operations::IssueOperation::ConvertedToDiscussion
          headers = headers.with_in_reply_to(issue.message_id)
        else
          headers
        end

        headers.build
      end

      sig { returns(Layouts::Basic) }
      def render
        repository = issue.repository
        from = FromAddress.new(author: author)
        reasons_explainer = ReasonsExplainer.new
        to = repository.present? ? NoReplyAddress.new(name: repository.name_with_display_owner, handle: repository.to_s || "") : ""
        unsubscribe_url_templates = UnsubscribeUrlTemplates.new

        Layouts::Basic.new(
          body: body.html,
          from: from.serialize,
          headers: headers,
          reasons_to_words: reasons_explainer.serialize,
          subject: subject,
          text_body: body.text,
          to: to.to_s,
          unsubscribe_url_templates: unsubscribe_url_templates.serialize,
          url: issue.permalink,
        )
      end

      private

      sig { returns(::Issue) }
      attr_reader :issue
      sig { returns(Author) }
      attr_reader :author
      sig { returns(Operations::IssueOperation) }
      attr_reader :operation
      sig { returns(Context) }
      attr_reader :context

      sig { returns(Body) }
      def body
        case operation
        when Operations::IssueOperation::Create,
          Operations::IssueOperation::Update
          IssueBody.new(issue: issue)
        else
          EventBody.new(operation: operation, context: context)
        end
      end

      sig { returns(String) }
      def subject
        subject = IssueSubject.new(issue: issue, repository: issue.repository)
        case operation
        when Operations::IssueOperation::Create,
          Operations::IssueOperation::Update
          subject.serialize
        else
          "Re: #{subject.serialize}"
        end
      end
    end
  end
end
