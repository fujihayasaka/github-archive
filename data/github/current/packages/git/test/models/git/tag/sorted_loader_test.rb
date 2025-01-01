# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class GitTagSortedLoaderTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :simple)

    [
      "refs/tags/2.0-release",
      "refs/tags/1.0-release",
      "refs/tags/v3/rc2",
      "refs/tags/v3/rc1",
    ].each do |name|
      Git::Ref.new(@repo, name).create(@repo.default_oid, @repo.owner)
    end

    example_repo_snapshot
  end

  setup do
    Spokesd.enable_spokesd

    example_repo_restore
  end

  context "#refs" do
    test "returns existing tags sorted" do
      refs = Git::Tag::SortedLoader.new(@repo).refs

      assert_equal 6, refs.size
      assert_equal ["v1", "v2", "v3/rc1", "v3/rc2", "1.0-release", "2.0-release"], refs.map(&:name)
    end

    test "does not hit repository backend for subsequent requests" do
      loader = Git::Tag::SortedLoader.new(@repo)
      loader.refs

      @repo.spokes_api.stubs(:list_references_with_details).raises(RuntimeError.new("should not be called"))
      loader.refs
    end

    context "with pattern" do
      test "returns existing matched tags sorted" do
        refs = Git::Tag::SortedLoader.new(@repo, pattern: "2").refs
        assert_equal 3, refs.size
        assert_equal ["v2", "v3/rc2", "2.0-release"], refs.map(&:name)
      end

      test "returns all tags with wildcard pattern" do
        refs = Git::Tag::SortedLoader.new(@repo, pattern: "*").refs

        assert_equal 6, refs.size
        assert_equal ["v1", "v2", "v3/rc1", "v3/rc2", "1.0-release", "2.0-release"], refs.map(&:name)
      end
    end
  end
end
