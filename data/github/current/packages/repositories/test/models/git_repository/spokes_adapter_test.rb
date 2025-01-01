# typed: true
# frozen_string_literal: true

require "test_helper"

class SpokesAdapterTestBase < GitHub::TestCase
  fixtures do
    @user = create :user, login: "bloop"
    @repo = create :repository, owner: @user, name: "spokes-adapter-test", from_example: :repository_test_simple
  end

  setup do
    Spokesd.enable_spokesd
  end
end

class SpokesAdapterReadObjectsTest < SpokesAdapterTestBase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures

  fixtures do
    @branch = @repo.heads.create("spokes-adapter-read-objects", @repo.default_branch_ref.commit.oid, @repo.owner)
    @commit = @branch.append_commit({
      committer: @user,
      message: "Commit message with trailing whitespaces in the trailers section. It also includes a non-existing short oid 30d833f00d \r\n\r\nSigned-off-by: Some Author <someone@example.com>\r\nCo-authored-by: Another Author <another@example.com>\r\n",
    }, @user)
    @huge_commit_truncated_by_gitrpc = @branch.append_commit({
      committer: @user,
      message: "This is going to be a huge commit message only truncated by GitRPC" * 10 * 1024,
    }, @user)
    @huge_commit_truncated_by_gitrpc_and_spokes = @branch.append_commit({
      committer: @user,
      message: "This is going to be a huge commit message truncated by GitRPC and Spokes" * 10 * 20 * 1024,
    }, @user)
    @commit_with_not_trailers = @branch.append_commit({
      committer: @user,
      message: "Commit with text like trailers\n\nnot-a-trailer: this is not a trailer\n\n because it's not at the end",
    }, @user)
    @commit_with_mixed_trailers = @branch.append_commit({
      committer: @user,
      message: "Commit with text like trailers\n\nnot-a-trailer: this is not a trailer\n\n because it's not at the end\n\nsigned-off-by: @migue",
    }, @user)

    @master_oid = @repo.spokes_api.resolve_object(object_name: "refs/heads/master")
    @annotated_oid = @repo.spokes_api.resolve_object(object_name: "refs/tags/v1")
    @non_existent_oid = "0123456789012345678901234567890123456789"
    @invalid_oid = "12345"

    @commits_to_test_batching = (1..1100).map do |i|
      @branch.append_commit({
        committer: @user,
        message: "Commit to test batching #{i}",
      }, @user)
    end
  end

  test "read_objects: commit" do
    objects = @repo.read_objects([@commit.oid], feature_flag: :spokes_adapter_test)
    assert_equal 1, objects.size
    commit = objects[0]
    assert_equal "commit", commit["type"]
    assert_equal @commit.oid, commit["oid"]
    assert_equal "Commit message with trailing whitespaces in the trailers section. It also includes a non-existing short oid 30d833f00d \r\n\r\nSigned-off-by: Some Author <someone@example.com>\r\nCo-authored-by: Another Author <another@example.com>", commit["message"]
    signed_off_by = commit["trailers"]["signed-off-by"]
    assert_equal 1, signed_off_by.size
    assert_equal "Some Author <someone@example.com>", signed_off_by[0]
    coauthored_by = commit["trailers"]["co-authored-by"]
    assert_equal 1, coauthored_by.size
    assert_equal "Another Author <another@example.com>", coauthored_by[0]
    assert_equal 0, commit["message_shas"].size
  end

  test "read_objects: huge commit truncated only by GitRPC" do
    [true, false].each do |skip_bad|
      objects = @repo.read_objects([@huge_commit_truncated_by_gitrpc.oid], "commit", skip_bad, feature_flag: :spokes_adapter_test)
      assert_equal 1, objects.size
      commit = objects[0]
      assert_equal @huge_commit_truncated_by_gitrpc.oid, commit["oid"]
      assert_equal "commit", commit["type"]
    end
  end

  test "read_objects: huge commit truncated by GitRPC and Spokes" do
    [true, false].each do |skip_bad|
      objects = @repo.read_objects([@huge_commit_truncated_by_gitrpc_and_spokes.oid], "commit", skip_bad, feature_flag: :spokes_adapter_test)
      assert_equal 1, objects.size
      commit = objects[0]
      assert_equal @huge_commit_truncated_by_gitrpc_and_spokes.oid, commit["oid"]
      assert_equal "commit", commit["type"]
    end
  end

  test "read_objects: commit with not-trailers in the message" do
    objects = @repo.read_objects([@commit_with_not_trailers.oid], "commit", true, feature_flag: :spokes_adapter_test)
    assert_equal 1, objects.size
    commit = objects[0]
    assert_equal @commit_with_not_trailers.oid, commit["oid"]
    assert_equal "commit", commit["type"]
    assert_equal "Commit with text like trailers\n\nnot-a-trailer: this is not a trailer\n\n because it's not at the end", commit["message"]
    assert_equal 0, commit["trailers"].size
  end

  test "read_objects: commit with not-trailers in the message and a real one" do
    objects = @repo.read_objects([@commit_with_mixed_trailers.oid], "commit", true, feature_flag: :spokes_adapter_test)
    assert_equal 1, objects.size
    commit = objects[0]
    assert_equal @commit_with_mixed_trailers.oid, commit["oid"]
    assert_equal "commit", commit["type"]
    assert_equal "Commit with text like trailers\n\nnot-a-trailer: this is not a trailer\n\n because it's not at the end\n\nsigned-off-by: @migue", commit["message"]
    assert_equal 1, commit["trailers"].size
    signed_off_by = commit["trailers"]["signed-off-by"]
    assert_equal 1, signed_off_by.size
    assert_equal "@migue", signed_off_by[0]
  end

  test "read_objects: request more than 1000 oids" do
    objects = @repo.read_objects(@commits_to_test_batching.map { |commit| commit.oid }, "commit", true, feature_flag: :spokes_adapter_test)
    assert_equal 1100, objects.size
    objects.each_with_index do |commit, i|
      assert_equal "commit", commit["type"]
      assert_equal @commits_to_test_batching[i].oid, commit["oid"]
      assert_equal "Commit to test batching #{i + 1}", commit["message"]
    end
  end

  context "read_object_headers" do
    test "with valid oids" do
      result = @repo.read_object_headers([@master_oid, @annotated_oid])
      assert_equal(
       [
           { "type" => "commit", "size" => 212 },
           { "type" => "tag", "size" => 138 },
       ],
        result
      )
    end
    test "with an invalid oid" do
      assert_raises(GitRPC::InvalidFullOid) do
        @repo.read_object_headers([@master_oid, @invalid_oid])
      end
    end

    test "with a non-existent oid" do
      assert_raises(GitRPC::ObjectMissing) do
        @repo.read_object_headers([@master_oid, @non_existent_oid])
      end
    end

    context "caching" do
      test "caches results" do
        with_cache_enabled do
          result = @repo.read_object_headers([@master_oid, @annotated_oid])

          SpokesAPI::Client.any_instance.stubs(:resolve_objects).raises(RuntimeError)

          # should not call backend
          cached_result = @repo.read_object_headers([@master_oid, @annotated_oid])

          assert_equal result, cached_result
        end
      end
    end
  end
end

class SpokesAdapterReadRefTest < SpokesAdapterTestBase
  fixtures do
    branch_names = []
    branch_names << "foo"
    branch_names << "branch/with/a/slash-and-dash"
    # "Mahjong" in Cantonese, Korean, and Thai.
    branch_names << "麻將"
    branch_names << "마작"
    branch_names << "ไพ่นกกระจอก"
    # 안녕하세요 (annyeonghaseyo) = hello (in Korean)
    branch_names << String.new("\xBE\xC8\xB3\xE7\xC7\xCF\xBC\xBC\xBF\xE4", encoding: Encoding.find("ASCII-8BIT"))

    @branches = branch_names.map do |branch|
      @repo.heads.create(branch, @repo.default_branch_ref.commit.oid, @repo.owner).name
    end

    example_repo_snapshot
  end

  setup do
    example_repo_restore

    # Cache key is dynamic (based on repository key/ref key), so set it up as a lambda
    @cache_key = lambda do
      "v2:spokes_adapter:#{@repo.rpc.repository_key}:#{@repo.rpc.repository_reference_key}:get_default_branch"
    end
  end

  test "get_default_branch" do
    with_cache_enabled do
      @branches.each do |branch|
        @repo.update_default_branch(branch)
        ref = @repo.get_default_branch
        assert_equal Encoding::UTF_8, ref.encoding
        assert_equal "refs/heads/#{branch.dup.force_encoding("UTF-8")}", ref
        assert_equal ref, GitHub.cache.get(@cache_key.call)
      end
    end
  end

  test "get_default_branch with repo missing on disk" do
    @repo.remove_from_disk
    assert_raises(SpokesAPI::NotFound) { @repo.get_default_branch }
  end
end

class SpokesAdapterReadRefsTest < SpokesAdapterTestBase
  fixtures do
    @master_oid = @repo.spokes_api.resolve_object(object_name: "refs/heads/master")
    @annotated_oid = @repo.spokes_api.resolve_object(object_name: "refs/tags/v1")
    @tag_oid = @repo.spokes_api.resolve_object(object_name: "refs/tags/v2")
  end

  setup do
    # Cache key is dynamic (based on repository key/ref key), so set it up as a lambda
    @gitrpc_cache_key = lambda do |refname|
      encoded_refname = Digest::SHA256.hexdigest(refname)
      "v2:#{@repo.rpc.repository_key}:#{@repo.rpc.repository_reference_key}:read_qualified_ref:v2:#{encoded_refname}"
    end

    @spokes_adapter_cache_key = lambda do |refname|
      encoded_refname = Digest::SHA256.hexdigest(refname)
      "v2:spokes_adapter:#{@repo.rpc.repository_key}:#{@repo.rpc.repository_reference_key}:resolve_references:v1:#{encoded_refname}"
    end
  end

  context "resolve_references" do
    test "with valid references" do
      result = @repo.resolve_references(%w[refs/heads/master refs/tags/v1])
      assert_equal(
        [
          ["refs/heads/master", @master_oid],
          ["refs/tags/v1", @annotated_oid]
        ],
        result
      )
    end

    test "with partial success" do
      result = @repo.resolve_references(%w[
        refs/heads/master
        refs/heads/foobar
        refs/tags/v1
      ])
      assert_equal(
        [
          ["refs/heads/master", @master_oid],
          ["refs/heads/foobar", nil],
          ["refs/tags/v1", @annotated_oid]
        ],
        result
      )
      assert_equal [["refs/heads/foobar", nil]], @repo.resolve_references(%w[refs/heads/foobar])
    end

    test "with batching" do
      # Artificially lower the batch size
      SpokesAPI::Client.stubs(:resolve_references_ref_limit).returns(2)

      result = @repo.resolve_references(%w[
        refs/heads/master
        refs/heads/foobar
        refs/tags/v1
      ])
      assert_equal(
        [
          ["refs/heads/master", @master_oid],
          ["refs/heads/foobar", nil],
          ["refs/tags/v1", @annotated_oid]
        ],
        result
      )
    end

    context "caching" do
      test "caches results" do
        with_cache_enabled do
          result = @repo.resolve_references(%w[
            refs/heads/master
            refs/heads/foobar
          ])

          SpokesAPI::Client.any_instance.stubs(:resolve_references).raises(RuntimeError)

          # should not invoke backend
          cached_result = @repo.resolve_references(%w[
            refs/heads/foobar
            refs/heads/master
          ])

          assert_equal result, cached_result.reverse
        end
      end

      test "gets partial cached results" do
        with_cache_enabled do
          result = @repo.resolve_references(%w[
            refs/heads/master
            refs/heads/foobar
          ])

          SpokesAPI::Client.any_instance.expects(:resolve_references)
            .with(%w[refs/tags/v1])
            .once
            .returns([["refs/tags/v1", @tag_oid]])

          # should not invoke backend
          cached_result = @repo.resolve_references(%w[
            refs/heads/master
            refs/tags/v1
            refs/heads/foobar
          ])

          expected_result = [
            ["refs/heads/master", @master_oid],
            ["refs/tags/v1", @tag_oid],
            ["refs/heads/foobar", nil]
          ]
          assert_equal expected_result, cached_result
        end
      end

      test "caches in SpokesAdapter" do
        found_gitrpc_key = @gitrpc_cache_key.call("refs/heads/master")
        missing_gitrpc_key = @gitrpc_cache_key.call("refs/heads/foobar")
        found_spokes_adapter_key = @spokes_adapter_cache_key.call("refs/heads/master")
        missing_spokes_adapter_key = @spokes_adapter_cache_key.call("refs/heads/foobar")

        with_cache_enabled do
          result = @repo.resolve_references(%w[
            refs/heads/master
            refs/heads/foobar
          ])

          cache_results = GitHub.cache.get_multi([
            found_gitrpc_key,
            missing_gitrpc_key,
            found_spokes_adapter_key,
            missing_spokes_adapter_key
          ])
          assert_equal 2, cache_results.size

          refute cache_results.has_key?(found_gitrpc_key)
          refute cache_results.has_key?(missing_gitrpc_key)

          assert cache_results.has_key?(found_spokes_adapter_key)
          assert_equal  @master_oid, cache_results[found_spokes_adapter_key]
          assert cache_results.has_key?(missing_spokes_adapter_key)
          assert_nil cache_results[missing_spokes_adapter_key]
        end
      end
    end
  end
end
