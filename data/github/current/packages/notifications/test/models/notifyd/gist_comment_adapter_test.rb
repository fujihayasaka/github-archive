# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class GistCommentAdapterTest < GitHub::TestCase
    fixtures do
      @mentioned_user = create(:user)
      @gist_author = create(:user)
      @gist = create(:gist, user: @gist_author)
      @user = create(:user)
      @gist_comment = create(:gist_comment, body: "@#{@mentioned_user} yeah?", gist: @gist, user: @user)
      @org = create(:organization)
      @gist_org = create(:gist, user: @org)
      @gist_comment_org = create(:gist_comment, gist: @gist_org)
    end

    test "matches for gist comments" do
      assert adapter(@gist_comment).matches?
    end

    test "does not match if the gist is missing" do
      @gist_comment.gist.delete
      @gist_comment.reload

      refute adapter(@gist_comment).matches?
    end


    test "does return notify feature flag value" do
      assert_equal GitHub.flipper[:notifyd_gist_comment_notify], adapter(@gist_comment).notify_feature_flag
    end


    test "related_topics" do
      related_topics = adapter(@gist_comment).related_topics

      assert_equal related_topics.size, 1
      assert_equal related_topics, [
        { type: "gist", value: @gist_comment.gist.id.to_s },
      ]
    end

    context "attributes" do
      test "when trigger is create" do
        attributes = adapter(@gist_comment, { operation: "create" }).attributes.sort_by { |a| a[:name] }

        assert_equal attributes.size, 2
        assert_equal attributes[0], { name: "thread_participant_activity", value: "true" }
        assert_equal attributes[1], { name: "thread_type", value: "gist" }
      end

      test "when trigger is update" do
        attributes = adapter(@gist_comment, { operation: "update" }).attributes

        assert_equal attributes.size, 1
        assert_equal attributes[0], { name: "thread_type", value: "gist" }
      end
    end

    test "owner_id" do
      refute_nil adapter(@gist_comment).owner_id
      assert_equal adapter(@gist_comment).owner_id, @gist_comment.gist.user.id
    end

    context "owner type" do
      test "for an organization is :organization" do
        org = create(:organization)
        gist = create(:gist, user: org)
        gist_comment = create(:gist_comment, gist: gist)
        assert_equal adapter(gist_comment).owner_type, :organization
      end

      test "for a user is :user" do
        assert_equal adapter(@gist_comment).owner_type, :user
      end
    end

    test "authzd_attributes" do
      expected_attrs = @gist_comment.permissions_wrapper.serialized_subject_attributes
      expected_attrs << Authzd::Proto::Attribute.wrap("actor.spammy", @user.spammy?)
      expected_attrs << Authzd::Proto::Attribute.wrap("actor.suspended", @user.suspended?)
      assert_equal adapter(@gist_comment).authzd_attributes.to_s, expected_attrs.to_s
    end

    context "saml_enforcement" do
      test "for user without org" do
        assert_equal adapter(@gist_comment).saml_enforcement, { skip_enforcement: true }
      end

      test "for user with org" do
        org = create(:organization)
        gist = create(:gist, user: org)
        gist_comment = create(:gist_comment, gist: gist)
        assert_equal adapter(gist_comment).saml_enforcement, { organization_id: org.id }
      end
    end

    test "email_layout" do
      layout = adapter(@gist_comment, { actor_login: "test_login", operation: "create" }).email_layout
      assert_equal layout.subject, "Re: #{@gist_comment.gist.name_with_title}"
      assert_equal layout.body, "<strong>@#{@gist_comment.user.login}</strong> commented on this gist. <hr/>\n#{@gist_comment.body_html}"
      assert_equal layout.text_body, "@#{@gist_comment.user.login} commented on this gist:\n\n#{@gist_comment.body}"
      assert_equal layout.from.name, @gist_comment.user.safe_profile_name
      assert_equal layout.from.email, ""
      assert_equal layout.url, @gist_comment.permalink
      assert_equal layout.to, "#{@gist_comment.user.login} <#{@gist_comment.user.login}@noreply.#{GitHub.urls.smtp_domain}>"
      refute_nil layout.unsubscribe_url_templates["footer"]
      refute_nil layout.unsubscribe_url_templates["header"]
      refute_nil layout.reasons_to_words
    end

    test "email_layout headers" do
      layout = adapter(@gist_comment, { actor_login: "test_login", operation: "create" }).email_layout
      headers = Notifyd::EmailHeaders.new(@gist_comment, @gist_comment.gist, "test_login").build
      assert_equal layout.headers.to_h["Message-ID"], headers[:"Message-ID"]
      assert_equal layout.headers.to_h["Precedence"], headers[:"Precedence"]
      assert_equal layout.headers.to_h["Return-Path"], headers[:"Return-Path"]
      assert_equal layout.headers.to_h["X-GitHub-Sender"], headers[:"X-GitHub-Sender"]
      assert_equal layout.headers.to_h["List-Id"], "#{@gist_comment.gist.user} <#{@gist_comment.gist.user}.#{@gist_comment.gist.user}.github.com>"
      assert_equal layout.headers.to_h["List-Archive"], @gist_comment.gist.user.permalink
    end

    context "explicit_recipients" do
      test "for create action" do
        another_user = create(:user)
        @gist_comment.body = "@#{@gist_author.login} yeah? and @#{another_user.login}"

        explicit_recipients = adapter(@gist_comment, { current_body: @gist_comment.body, operation: "create" }).explicit_recipients
        assert explicit_recipients.include?({ reason: "mention", users: [User.new(id: @gist_author.id), User.new(id: another_user.id)] })
        assert explicit_recipients.include?({ reason: "comment", users: [User.new(id: @gist_comment.user.id)] })
      end

      test "for update action" do
        another_user = create(:user)
        previous_body = @gist_comment.body
        @gist_comment.body += " and @#{another_user.login}"

        assert adapter(@gist_comment, { previous_body: previous_body, current_body: @gist_comment.body, operation: "update" })
          .explicit_recipients.include?({ reason: "mention", users: [User.new(id: another_user.id)] })
      end


      test "for update and no user mention" do
        previous_body = @gist_comment.body
        @gist_comment.body = "no user mention"

        assert_equal adapter(@gist_comment, { previous_body: previous_body, current_body: @gist_comment.body, operation: "update" }).explicit_recipients, []
      end

      test "for unknown action" do
        assert_equal adapter(@gist_comment, { operation: "unknown" }).explicit_recipients, []
      end
    end

    private

    def adapter(gist_comment, context = {})
      Notifyd::GistCommentAdapter.new(gist_comment, context)
    end
  end
end
