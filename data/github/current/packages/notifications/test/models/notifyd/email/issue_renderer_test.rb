# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "./dummy_author"

module Notifyd::Email
  class IssueRendererTest < GitHub::TestCase
    Operation = Notifyd::Operations::IssueOperation

    fixtures do
      @user = create(:user)
      @mentioned_user = create(:user)
      @issue = create(:issue, user: @user, body: "@#{@mentioned_user} yeah?")
    end

    setup do
      @context = { actor_login: "test_login", actor_id: "1" }
      @author = DummyAuthor.new
    end

    context "#render" do
      test "email layout fields with url templates feature enabled" do
        layout = IssueRenderer.new(issue: @issue, author: @author, operation: Operation::Create, context: @context).render

        assert_equal layout.subject, "[#{@issue.repository.name_with_display_owner}] #{@issue.title} (Issue ##{@issue.number})"
        assert_equal layout.body, @issue.body_html
        assert_equal layout.text_body, @issue.body
        assert_equal layout.from&.name, @author.profile_name
        assert_equal layout.from&.email, ""
        assert_equal layout.url, @issue.permalink
        assert_equal layout.to, "#{@issue.repository.name_with_owner} <#{@issue.repository}@noreply.github.com>"
        refute_nil layout.reasons_to_words
        refute_nil layout.unsubscribe_url_templates
      end

      test "email layout headers" do
        layout = IssueRenderer.new(issue: @issue, author: @author, operation: Operation::Create, context: @context).render
        headers = Notifyd::EmailHeaders.new(@issue, @issue.repository, "test_login").build

        assert_equal layout.headers.to_h["Message-ID"], headers[:"Message-ID"]
        assert_nil layout.headers.to_h["In-Reply-To"]
        assert_nil layout.headers.to_h["References"]
        assert_equal layout.headers.to_h["Precedence"], headers[:"Precedence"]
        assert_equal layout.headers.to_h["Return-Path"], headers[:"Return-Path"]
        assert_equal layout.headers.to_h["X-GitHub-Sender"], headers[:"X-GitHub-Sender"]
        assert_equal layout.headers.to_h["List-Id"], headers[:"List-Id"]
        assert_equal layout.headers.to_h["List-Archive"], headers[:"List-Archive"]
        assert_equal layout.headers.to_h["List-Post"], headers[:"List-Post"]
      end

      context "body" do
        test "for create operation" do
          layout = IssueRenderer.new(issue: @issue, author: @author, operation: Operation::Create, context: @context).render

          assert_equal layout.body, @issue.body_html_for_email
        end

        test "for update operation" do
          layout = IssueRenderer.new(issue: @issue, author: @author, operation: Operation::Update, context: @context).render

          assert_equal layout.body, @issue.body_html_for_email
        end

        test "for labeled operations" do
          label = create(:label, repository: @issue.repository)
          context = @context.merge(added_label_id: label.id)
          layout = IssueRenderer.new(issue: @issue, author: @author, operation: Operation::Labeled, context: context).render

          assert_equal layout.body, "Issue was assigned label: #{label.name}"
        end

        test "for unlabeled operations" do
          label = create(:label, repository: @issue.repository)
          context = @context.merge(removed_label_id: label.id)
          layout = IssueRenderer.new(issue: @issue, author: @author, operation: Operation::Unlabeled, context: context).render

          assert_equal layout.body, "Issue was unassigned label: #{label.name}"
        end

        test "for assinged operations" do
          user = create(:user)
          event = create(:issue_event, issue: @issue, event: "assigned", actor: user)
          context = @context.merge(assignee_id: user.id, event_id: event.id)
          layout = IssueRenderer.new(issue: @issue, author: @author, operation: Operation::Assigned, context: context).render

          assert_equal layout.body, event.issue_event_notification.body_html_for_email.to_str
          assert_equal layout.text_body, event.issue_event_notification.body.to_str
        end

        test "for unassinged operations" do
          user = create(:user)
          event = create(:issue_event, issue: @issue, event: "unassigned", actor: user)
          context = @context.merge(assignee_id: user.id, event_id: event.id)
          layout = IssueRenderer.new(issue: @issue, author: @author, operation: Operation::Assigned, context: context).render

          assert_equal layout.body, event.issue_event_notification.body_html_for_email.to_str
          assert_equal layout.text_body, event.issue_event_notification.body.to_str
        end

        test "for closed operations" do
          event = create(:issue_event, issue: @issue, event: "closed")
          context = @context.merge(event_id: event.id)
          layout = IssueRenderer.new(issue: @issue, author: @author, operation: Operation::Closed, context: context).render

          assert_equal layout.body, event.issue_event_notification.body_html_for_email.to_str
          assert_equal layout.text_body, event.issue_event_notification.body.to_str
        end

        test "for reopened operations" do
          event = create(:issue_event, issue: @issue, event: "reopened")
          context = @context.merge(event_id: event.id)
          layout = IssueRenderer.new(issue: @issue, author: @author, operation: Operation::Reopened, context: context).render

          assert_equal layout.body, event.issue_event_notification.body_html_for_email.to_str
          assert_equal layout.text_body, event.issue_event_notification.body.to_str
        end

        test "for converted to discussion operations" do
          event = create(:issue_event, issue: @issue, event: "converted_to_discussion", subject: create(:discussion))
          context = @context.merge(event_id: event.id)
          layout = IssueRenderer.new(issue: @issue, author: @author, operation: Operation::ConvertedToDiscussion, context: context).render

          assert_equal layout.body, event.issue_event_notification.body_html_for_email.to_str
          assert_equal layout.text_body, event.issue_event_notification.body.to_str
        end
      end
    end
  end
end
