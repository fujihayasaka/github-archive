# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  module Email
    class MemexProjectStatusRendererTest < GitHub::TestCase

      fixtures do
        @admin = create(:user)
        @organization = create(:organization, admin: @admin, login: "test-org")
        @member = create(:verified_user).tap { |u| @organization.add_member(u) }
        @organization_memex_project = create(:memex_project, title: "Organization Project", owner: @organization)
        @user = create(:verified_user, login: "my-user")
        @user_memex_project = create(:memex_project, owner: @user, title: "User Project")
      end

      def assert_match_status_values(memex_project_status, body)
        assert_match "Start date:", body
        assert_match memex_project_status.start_date.iso8601, body
        assert_match "Target date:", body
        assert_match memex_project_status.target_date.iso8601, body
        assert_match "Status:", body
        assert_match memex_project_status.status_name_html, body
      end

      def refute_status_value_headings(body)
        refute_includes "Start date:", body
        refute_includes "Target date:", body
        refute_includes "Status:", body
      end

      test "#render for organization owned MemexProject" do
        memex_project_status = create(:memex_project_status, creator: @admin, memex_project: @organization_memex_project)
        author = Notifyd::Email::AuthorUser.new(user: @admin)
        layout = Notifyd::Email::MemexProjectStatusRenderer.new(
          memex_project_status: memex_project_status,
          author: author,
          actor: @admin,
        ).render

        assert_equal "<test-org/projects/#{@organization_memex_project.id}/statuses/#{memex_project_status.id}@github.com>", layout.headers["Message-ID"]
        assert_equal @organization_memex_project.permalink, layout.headers["List-Archive"]
        assert_equal @admin.display_login, layout.headers["X-GitHub-Sender"]
        assert_equal "[test-org] Organization Project (Project #1) Status update", layout.subject
        assert_match_status_values(memex_project_status, layout.body)
        assert_match memex_project_status.body_html_for_email, layout.body
        assert_match_status_values(memex_project_status, layout.text_body)
        assert_match memex_project_status.body_text, layout.text_body
        assert_equal "Organization Project <test-org@noreply.github.com>", layout.to
        assert_equal layout.from&.name, @admin.safe_profile_name
        assert_equal layout.reasons_to_words, {}
        assert_equal memex_project_status.permalink, layout.url
        assert_nil layout.unsubscribe_url_templates
      end

      test "#render for user owned MemexProject" do
        memex_project_status = create(:memex_project_status, creator: @user, memex_project: @user_memex_project)
        author = Notifyd::Email::AuthorUser.new(user: @user)
        layout = Notifyd::Email::MemexProjectStatusRenderer.new(
          memex_project_status: memex_project_status,
          author: author,
          actor: @user,
        ).render

        assert_equal "<my-user/projects/#{@user_memex_project.id}/statuses/#{memex_project_status.id}@github.com>", layout.headers["Message-ID"]
        assert_equal @user_memex_project.permalink, layout.headers["List-Archive"]
        assert_equal @user.display_login, layout.headers["X-GitHub-Sender"]
        assert_equal "[my-user] User Project (Project #1) Status update", layout.subject
        assert_match_status_values(memex_project_status, layout.body)
        assert_match memex_project_status.body_html_for_email, layout.body
        assert_match_status_values(memex_project_status, layout.text_body)
        assert_match memex_project_status.body_text, layout.text_body
        assert_equal "User Project <my-user@noreply.github.com>", layout.to
        assert_equal layout.from&.name, @user.safe_profile_name
        assert_equal layout.reasons_to_words, {}
        assert_equal memex_project_status.permalink, layout.url
        assert_nil layout.unsubscribe_url_templates
      end

      test "#render status update without values" do
        memex_project_status = create(:memex_project_status, creator: @admin, memex_project: @organization_memex_project, status_value: {
          "status_id" => nil,
          "start_date" => nil,
          "target_date" => nil,
        }.to_json)
        author = Notifyd::Email::AuthorUser.new(user: @admin)
        layout = Notifyd::Email::MemexProjectStatusRenderer.new(
          memex_project_status: memex_project_status,
          author: author,
          actor: @admin,
        ).render

        refute_status_value_headings(layout.body)
        assert_match memex_project_status.body_html_for_email, layout.body
        refute_status_value_headings(layout.text_body)
        assert_match memex_project_status.body_text, layout.text_body
      end
    end
  end
end
