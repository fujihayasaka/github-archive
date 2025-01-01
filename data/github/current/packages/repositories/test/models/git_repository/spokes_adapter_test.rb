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

    @branches = Spokesd.with_spokesd_disabled do
      branch_names.map do |branch|
        @repo.heads.create(branch, @repo.default_branch_ref.commit.oid, @repo.owner).name
      end
    end

    example_repo_snapshot
  end

  setup do
    example_repo_restore

    # Cache key is dynamic (based on repository key/ref key), so set it up as a lambda
    @cache_key = lambda do
      func_fragment = @repo.feature_enabled?(:get_default_branch_spokes) ? "get_default_branch" : "read_symbolic_ref:HEAD"
      "v2:spokes_adapter:#{@repo.rpc.repository_key}:#{@repo.rpc.repository_reference_key}:#{func_fragment}"
    end
  end

  test "read_symbolic_ref" do
    with_cache_enabled do
      @branches.each do |branch|
        Spokesd.with_spokesd_disabled { @repo.update_default_branch(branch) }
        ref = @repo.get_default_branch
        assert_equal Encoding::UTF_8, ref.encoding
        assert_equal "refs/heads/#{branch.dup.force_encoding("UTF-8")}", ref
        assert_equal ref, GitHub.cache.get(@cache_key.call)
      end
    end
  end

  test "read_symbolic_ref with repo missing on disk" do
    @repo.remove_from_disk
    error_class = @repo.feature_enabled?(:get_default_branch_spokes) ? SpokesAPI::NotFound : GitRPC::InvalidRepository
    assert_raises(error_class) { @repo.get_default_branch }
  end
end

class SpokesAdapterReadRefsTest < SpokesAdapterTestBase
  fixtures do
    @master_oid = @repo.rev_parse("refs/heads/master")
    @annotated_oid = @repo.rev_parse("refs/tags/v1")
    @tag_oid = @repo.rev_parse("refs/tags/v2")
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
      result = @repo.resolve_references(%w[refs/heads/master refs/tags/v1], source: :test)
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
      ], source: :test)
      assert_equal(
        [
          ["refs/heads/master", @master_oid],
          ["refs/heads/foobar", nil],
          ["refs/tags/v1", @annotated_oid]
        ],
        result
      )
      assert_equal [["refs/heads/foobar", nil]], @repo.resolve_references(%w[refs/heads/foobar], source: :test)
    end

    test "with batching" do
      # Artificially lower the batch size
      SpokesAPI::Client.stubs(:resolve_references_ref_limit).returns(2)

      result = @repo.resolve_references(%w[
        refs/heads/master
        refs/heads/foobar
        refs/tags/v1
      ], source: :test)
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
        # Disable experiment comparing GitRPC to SpokesAPI response to simplify
        # response mocks.
        GitHub::Experiment.any_instance.stubs(:enabled?).returns(false)

        with_cache_enabled do
          result = @repo.resolve_references(%w[
            refs/heads/master
            refs/heads/foobar
          ], source: :test)

          SpokesAPI::Client.any_instance.stubs(:resolve_references).raises(RuntimeError)
          GitRPC::Client.any_instance.stubs(:send_message).raises(RuntimeError)

          # should not invoke backend
          cached_result = @repo.resolve_references(%w[
            refs/heads/foobar
            refs/heads/master
          ], source: :test)

          assert_equal result, cached_result.reverse
        end
      end

      test "gets partial cached results" do
        # Disable experiment comparing GitRPC to SpokesAPI response to simplify
        # response mocks.
        GitHub::Experiment.any_instance.stubs(:enabled?).returns(false)

        with_cache_enabled do
          result = @repo.resolve_references(%w[
            refs/heads/master
            refs/heads/foobar
          ], source: :test)

          if TestEnv.test_all_features?
            SpokesAPI::Client.any_instance.expects(:resolve_references)
              .with(%w[refs/tags/v1])
              .once
              .returns([["refs/tags/v1", @tag_oid]])
          else
            GitRPC::Client.any_instance.expects(:send_message)
            .with(:read_qualified_refs, %w[refs/tags/v1])
            .once
            .returns([@tag_oid])
          end

          # should not invoke backend
          cached_result = @repo.resolve_references(%w[
            refs/heads/master
            refs/tags/v1
            refs/heads/foobar
          ], source: :test)

          expected_result = [
            ["refs/heads/master", @master_oid],
            ["refs/tags/v1", @tag_oid],
            ["refs/heads/foobar", nil]
          ]
          assert_equal expected_result, cached_result
        end
      end

      test "caches in GitRPC when caching feature is disabled" do
        skip if TestEnv.test_all_features?

        found_gitrpc_key = @gitrpc_cache_key.call("refs/heads/master")
        missing_gitrpc_key = @gitrpc_cache_key.call("refs/heads/foobar")
        found_spokes_adapter_key = @spokes_adapter_cache_key.call("refs/heads/master")
        missing_spokes_adapter_key = @spokes_adapter_cache_key.call("refs/heads/foobar")

        with_cache_enabled do
          result = @repo.resolve_references(%w[
            refs/heads/master
            refs/heads/foobar
          ], source: :test)

          cache_results = GitHub.cache.get_multi([
            found_gitrpc_key,
            missing_gitrpc_key,
            found_spokes_adapter_key,
            missing_spokes_adapter_key
          ])
          assert_equal 2, cache_results.size

          assert cache_results.has_key?(found_gitrpc_key)
          assert_equal  @master_oid, cache_results[found_gitrpc_key]
          assert cache_results.has_key?(missing_gitrpc_key)
          assert_nil cache_results[missing_gitrpc_key]

          refute cache_results.has_key?(found_spokes_adapter_key)
          refute cache_results.has_key?(missing_spokes_adapter_key)
        end
      end

      test "caches in SpokesAdapter when caching feature is enabled" do
        skip if TestEnv.test_all_features?

        found_gitrpc_key = @gitrpc_cache_key.call("refs/heads/master")
        missing_gitrpc_key = @gitrpc_cache_key.call("refs/heads/foobar")
        found_spokes_adapter_key = @spokes_adapter_cache_key.call("refs/heads/master")
        missing_spokes_adapter_key = @spokes_adapter_cache_key.call("refs/heads/foobar")

        @repo.enable_feature(:resolve_references_cache_spokes_adapter)

        with_cache_enabled do
          result = @repo.resolve_references(%w[
            refs/heads/master
            refs/heads/foobar
          ], source: :test)

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

      test "cannot roll out Spokes API endpoint without caching in SpokesAdapter" do
        skip if TestEnv.test_all_features?

        GitHub::Experiment.any_instance.stubs(:enabled?).returns(false)
        SpokesAPI::Client.any_instance.stubs(:resolve_references).raises(RuntimeError)
        @repo.enable_feature(:resolve_references_spokes_test)

        # Does not raise because Spokes API is not called
        @repo.resolve_references(%w[
            refs/heads/master
            refs/heads/foobar
          ], source: :test)

        @repo.enable_feature(:resolve_references_cache_spokes_adapter)

        assert_raises(RuntimeError) do
          @repo.resolve_references(%w[
              refs/tags/v1
            ], source: :test)
        end
      end
    end
  end
end
