# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class LegacySearchResultSerializersTest < Api::SerializerTestCase
  setup do
    @user = User.new login: "l", gravatar_id: "g", created_at: 6.minutes.ago
    @user.profile = Profile.new name: "name", company: "company",
      blog: "http://example.com", location: "location",
      email: "x@example.com"
    @repo = Repository.new owner: @user, name: "r",
      pushed_at: 1.minute.ago, created_at: 5.minutes.ago
    @issue = Issue.new repository: @repo, user: @user, number: 1,
      state: "open", title: "t", body: "b",
      created_at: Time.now, updated_at: Time.now
    @pr_issue = Issue.new repository: @repo, user: @user, number: 2,
      state: "open", title: "t", body: "b",
      created_at: Time.now, updated_at: Time.now,
      pull_request_id: 123
    @user.id = 1
    @repo.id = 2
    @issue.id = 3
    @pr_issue.id = 4
  end

  test "#legacy_issue_search_result_hash" do
    api_media_type "application/vnd.github+json"

    output = serialize_hash_method(:legacy_issue_search_result_hash, @issue)
    assert output.key?("labels")
    assert output.key?("votes")
    assert output.key?("number")
    assert output.key?("position")
  end

  test "#legacy_issue_search_result_hash with a PR issue doesn't blow up" do
    api_media_type "application/vnd.github+json"

    assert_nothing_raised do
      serialize_hash_method(:legacy_issue_search_result_hash, @pr_issue)
    end
  end

  test "#legacy_repository_search_result_hash" do
    api_media_type "application/vnd.github+json"
    output = serialize_hash_method(:legacy_repository_search_result_hash, @repo, search_hit: {
      "language_id" => 303,
      "followers" => 0,
      "owner" => "l",
      "pushed_at" => Time.now,
      "created_at" => Time.now,
    })
    assert output.key?("type")
    assert output.key?("username")
    assert output.key?("name")
    assert output.key?("owner")
  end

  test "#legacy_user_search_result_hash" do
    api_media_type "application/vnd.github+json"
    output = serialize_hash_method(:legacy_user_search_result_hash, @user, search_hit: {
      "repos" => 0, "followers" => 1, "name" => "some name",
      "language" => "lang", "location" => "loc",
      "created_at" => "2013-02-26T09:07:41-05:00"
    })
    assert output.key?("id")
    assert output.key?("gravatar_id")
    assert output.key?("username")
    assert output.key?("login")


  end

  test "#legacy_user_email_result_hash" do
    api_media_type "application/vnd.github+json"
    output = serialize_hash_method(:legacy_user_email_result_hash, @user)
    assert output.key?("public_repo_count")
    assert output.key?("public_gist_count")
    assert output.key?("followers_count")
    assert output.key?("following_count")
  end
end
