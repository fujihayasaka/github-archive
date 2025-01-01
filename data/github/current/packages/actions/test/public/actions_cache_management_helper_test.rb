# typed: true
# frozen_string_literal: true

require "monolith-twirp-actionsresults-core"
require "github-launch"
require "test_helper"
require "test_helpers/actions_cache_test_helpers"

class ActionsCacheManagementHelperTest < GitHub::TestCase
  include ActionsCacheTestHelpers

  fixtures do
    @repo = create(:repository)
    @repo_global_id = GitHub.enterprise? ? @repo.global_relay_id : @repo.next_global_id
    @key = "setup-go-Linux-x64-ubuntu24-go-1.23.1-762782c46f257e4edb17e3335a4e5dc9d08d83753d9629dc7864f9a4188fe4d2"
    @scope = "refs/heads/main"
  end

  setup do
    @ts = Google::Protobuf::Timestamp.new(seconds: Time.now.to_i)
    @launch_caches = build_list(:launch_cache_entry, 4)
    @launch_cache_list_response = TwirpResponse.new(
      status: 200,
      call_succeeded: true,
      value: GitHub::Launch::Services::Artifactcache::ListCachesResponse.new(
        caches: @launch_caches,
        total_caches: @launch_caches.length,
      )
    )
    @results_caches = build_list(:results_cache_entry, 4)
    @results_cache_list_response = TwirpResponse.new(
      status: 200,
      call_succeeded: true,
      value: MonolithTwirp::ActionsResults::Core::V1::ListCachesResponse.new(
        caches: @results_caches,
        total_caches: @results_caches.length,
      )
    )
  end

  def expect_launch(method, args, response: nil)
    if response.nil?
      resp = TwirpResponse.new(value: nil, status: 200, call_succeeded: true)
    end

    Launch::Twirp::CacheClient
      .any_instance
      .expects(:rpc)
      .with(method, equals(args))
      .returns(response)
      .once
  end

  def expect_results(method, args, response: nil)
    if response.nil?
      resp = TwirpResponse.new(value: nil, status: 200, call_succeeded: true)
    end

    ActionsResults::Twirp::CacheClient
      .any_instance
      .expects(:rpc)
      .with(method, equals(args))
      .returns(response)
      .once
  end

  context "#get_repo_caches" do
    test "calls launch when flag is off" do
      disable_cache_v2!

      expect_launch(:ListCaches, {
        repository_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @repo_global_id),
        key: @key,
        scope: @scope,
        per_page: 30,
        page: 1,
        sort: "last_accessed_at",
        direction: "desc"
      }, response: @launch_cache_list_response)

      res = ActionsCacheManagementHelper.get_repo_caches(repo: @repo, key: @key, ref: @scope)

      expected = T.must(CacheList.from_launch(@launch_cache_list_response.value))
      assert_equal expected.total_caches, res.value.total_caches
      assert_equal expected.caches, res.value.caches
    end

    test "calls results when flag is on", skip_enterprise: true do
      enable_cache_v2!

      expect_results(:ListCaches, {
        repository_id: @repo.id,
        key: @key,
        scope: @scope,
        sort: ActionsResults::Twirp::CacheClient::Sort::SORT_LAST_ACCESSED_AT,
        direction: ActionsResults::Twirp::CacheClient::Direction::DIRECTION_DESC,
        page: 1,
        per_page: 30,
      }, response: @results_cache_list_response)

      res = ActionsCacheManagementHelper.get_repo_caches(repo: @repo, key: @key, ref: @scope)

      expected = T.must(CacheList.from_results(@results_cache_list_response.value))
      assert_equal expected.total_caches, res.value.total_caches
      assert_equal expected.caches, res.value.caches
    end
  end
end
