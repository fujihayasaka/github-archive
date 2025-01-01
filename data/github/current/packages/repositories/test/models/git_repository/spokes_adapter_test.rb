# typed: true
# frozen_string_literal: true

require "test_helper"

class SpokesAdapterTestBase < GitHub::TestCase
  fixtures do
    Spokesd.enable_spokesd
    @user = create(:user, login: "bloop")
    @repo = create(:repository, owner: @user, name: "spokes-adapter-test")
  end
end

class SpokesAdapterReadRefTest < SpokesAdapterTestBase
  setup do
    # Create the repo
    example_repo :repository_test_simple, @repo
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
      @repo.heads.create(branch, @repo.default_branch_ref.commit.oid, @repo.owner)
    end

    # Cache key is dynamic (based on repository key/ref key), so set it up as a lambda
    @cache_key = lambda { "v2:spokes_adapter:#{@repo.rpc.repository_key}:#{@repo.rpc.repository_reference_key}:read_symbolic_ref:HEAD" }
  end

  teardown do
    @repo.remove_from_disk
  end

  test "read_symbolic_ref" do
    with_cache_enabled do
      @branches.each do |branch|
        @repo.update_default_branch(branch.name)
        ref = @repo.get_default_branch
        assert_equal Encoding::UTF_8, ref.encoding
        assert_equal "refs/heads/#{branch.name.dup.force_encoding("UTF-8")}", ref
        assert_equal ref, GitHub.cache.get(@cache_key.call)
      end
    end
  end

  test "read_symbolic_ref with repo missing on disk" do
    @repo.remove_from_disk
    assert_raises(GitRPC::InvalidRepository) { @repo.get_default_branch }
  end

  test "async_get_default_branch" do
    with_cache_enabled do
      @branches.each do |branch|
        @repo.update_default_branch(branch.name)
        ref = @repo.async_get_default_branch.sync
        assert_equal Encoding::UTF_8, ref.encoding
        assert_equal "refs/heads/#{branch.name.dup.force_encoding("UTF-8")}", ref
        assert_equal ref, GitHub.cache.get(@cache_key.call)
      end
    end
  end
end
