# typed: true
# frozen_string_literal: true

require "test_helper"

class StorageAlambicPolicyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  setup do
    @avatar = Avatar.new(owner: @user, size: 0, content_type: "image/jpg")
  end

  context "generating a download url" do
    test "when a query is passed in the url has it in the query string" do
      @policy = Storage::AlambicPolicy.new(@avatar)
      query = URI.parse(@policy.download_url(some: "query")).query
      assert_equal "some=query", query
    end

    test "when the uploadable has a token, the token is in the query string" do
      @policy = Storage::AlambicPolicy.new(@avatar, actor: @user)
      query = URI.parse(@policy.download_url).query
      assert_match "token=", query
    end

    test "when the uploadable does not have a token and a query is not passed in, the query string is empty" do
      @policy = Storage::AlambicPolicy.new(@avatar)
      query = URI.parse(@policy.download_url).query
      assert_nil query
    end
  end

  context "stats" do
    test "for download" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      Storage::AlambicPolicy.new(@avatar).download_url

      assert stat = stats.timings("storage_policy.url")[0]
      assert_includes stat.tags, "policy:alambic"
      assert_includes stat.tags, "model:avatar"
      assert_includes stat.tags, "op:download"
    end

    test "for upload" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      Storage::AlambicPolicy.new(@avatar, actor: @user).policy_hash

      assert stat = stats.timings("storage_policy.url")[0]
      assert_includes stat.tags, "policy:alambic"
      assert_includes stat.tags, "model:avatar"
      assert_includes stat.tags, "op:upload"
    end
  end
end
