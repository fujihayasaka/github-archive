# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd::Mobile
  class ReleaseTest < GitHub::TestCase
    fixtures do
      @owner = create(:user, login: "owner")
      @author = create(:user, login: "author")
      @repo = create(:repository, owner: @owner, name: "repo", from_example: :simple)
      @release = create(:release, tag_name: "v1", name: "Version One!", author: @owner, repository: @repo, body: "<p>Hello world</p>")
    end

    test "layout #body" do
      layout = renderer(@release).render

      assert_equal @release.body, layout.body
    end

    test "layout #url" do
      layout = renderer(@release).render

      assert_equal @release.permalink, layout.url
    end

    test "layout #subtitle" do
      layout = renderer(@release).render

      assert_equal "owner/repo", layout.subtitle
    end

    test "author provile info" do
      layout = renderer(@release).render

      refute_predicate layout.avatar_url, :empty?
    end

    test "layout #title" do
      layout = renderer(@release).render

      assert_equal "Release v1 - Version One!", layout.title
    end

    test "layout #thread_id" do
      layout = renderer(@release).render

      assert_equal @release.permalink(include_host: false), layout.thread_id
    end

    test "layout #thread_type" do
      layout = renderer(@release).render

      assert_equal "release", layout.thread_type
    end

    private

    def renderer(release)
      ReleaseRenderer.new(release: release, author: AuthorUser.new(user: release.author))
    end
  end
end
