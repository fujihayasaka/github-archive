# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "./dummy_author"

module Notifyd::Mobile
  class MobilePullRequestTest < GitHub::TestCase
    test "#render" do
      repo = create(:repository, from_example: :simple)
      pr = PullRequest.create_for!(repo,
        user: repo.owner,
        base: "master",
        head: "cr-line-endings",
        title: "A title",
        body: "A body"
      )

      author = DummyAuthor.new
      layout = PullRequestRenderer.new(pull_request: pr, author: author).render

      assert_equal "@john_doe mentioned you", layout.title
      assert_equal "#{repo.name_with_display_owner} ##{pr.number}", layout.subtitle
      assert_equal pr.body, layout.body
      assert_equal pr.permalink, layout.url
      assert_equal author.avatar_url, layout.avatar_url
      assert_equal author.profile_name, layout.author_profile_name
      assert_equal author.username, layout.author_username
      assert_equal pr.permalink(include_host: false), layout.thread_id
      assert_equal "pull_request", layout.thread_type
    end
  end
end
