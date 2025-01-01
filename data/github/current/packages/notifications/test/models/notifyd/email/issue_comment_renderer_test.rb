# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "./dummy_author"

module Notifyd::Email
  class IssueCommentRendererTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
      @issue_comment = create(:issue_comment, body: "Hello there!")
      @issue = @issue_comment.issue
    end

    setup do
      @context = { actor_login: "test_login", actor_id: "1" }
      @author = DummyAuthor.new
    end

    context "#render" do
      test "email layout fields with url templates feature enabled" do
        layout = IssueCommentRenderer.new(issue: @issue, comment: @issue_comment, author: @author, context: @context).render

        assert_equal layout.subject, "Re: [#{@issue.repository.name_with_owner}] #{@issue.title} (Issue ##{@issue.number})"
        assert_equal layout.body, @issue_comment.body_html
        assert_equal layout.text_body, @issue_comment.body
        assert_equal layout.from&.name, @author.profile_name
        assert_equal layout.from&.email, ""
        assert_equal layout.url, @issue_comment.permalink
        assert_equal layout.to, "#{@issue.repository.name_with_owner} <#{@issue.repository}@noreply.github.com>"
        refute_nil layout.reasons_to_words
        refute_nil layout.unsubscribe_url_templates
      end

      test "email layout headers" do
        layout = IssueCommentRenderer.new(issue: @issue, comment: @issue_comment, author: @author, context: @context).render
        headers = Notifyd::EmailHeaders.new(@issue_comment, @issue.repository, "test_login").with_in_reply_to(@issue.message_id).build

        assert_equal layout.headers.to_h["Message-ID"], headers[:"Message-ID"]
        assert_equal layout.headers.to_h["In-Reply-To"], headers[:"In-Reply-To"]
        assert_equal layout.headers.to_h["References"], headers[:"References"]
        assert_equal layout.headers.to_h["Precedence"], headers[:"Precedence"]
        assert_equal layout.headers.to_h["Return-Path"], headers[:"Return-Path"]
        assert_equal layout.headers.to_h["X-GitHub-Sender"], headers[:"X-GitHub-Sender"]
        assert_equal layout.headers.to_h["List-Id"], headers[:"List-Id"]
        assert_equal layout.headers.to_h["List-Archive"], headers[:"List-Archive"]
        assert_equal layout.headers.to_h["List-Post"], headers[:"List-Post"]
      end
    end
  end
end
