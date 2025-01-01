# typed: true
# frozen_string_literal: true

require "test_helper"

class GitRefLoaderTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :simple)

    %w(refs/heads/topic refs/tags/2.0-release refs/__gh__/foobar refs/special/case).each do |name|
      Git::Ref.new(@repo, name).create(@repo.default_oid, @repo.owner)
    end

    @empty_repo = create(:repository, from_example: :empty)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  context "#qualified_ref" do
    test "returns existing ref within filter" do
      loader = Git::Ref::Loader.new(@repo, "default")
      refute_nil ref = loader.qualified_ref("refs/heads/master")
      assert_equal "refs/heads/master", ref.qualified_name

      loader = Git::Ref::Loader.new(@repo, "extended")
      refute_nil ref = loader.qualified_ref("refs/special/case")
      assert_equal "refs/special/case", ref.qualified_name

      loader = Git::Ref::Loader.new(@repo)
      refute_nil ref = loader.qualified_ref("refs/__gh__/foobar")
      assert_equal "refs/__gh__/foobar", ref.qualified_name
    end

    test "returns nil for non-existing ref" do
      loader = Git::Ref::Loader.new(@repo, "default")
      assert_nil loader.qualified_ref("refs/heads/foobar")
    end

    test "does not raise when loading symbolic ref" do
      @repo.rpc.update_symbolic_ref("refs/heads/foo", "refs/heads/does-not-exist") # invalid symref
      @repo.rpc.update_symbolic_ref("refs/heads/bar", "refs/heads/topic") # valid symref

      # This should not raise, and ignore the symbolic ref
      loader = Git::Ref::Loader.new(@repo, "extended")
      loader.refs

      assert_nil loader.qualified_ref("refs/heads/foo")
      refute_nil ref = loader.qualified_ref("refs/heads/bar")
      assert_equal "refs/heads/bar", ref.qualified_name
      assert_equal @repo.default_oid, ref.target_oid
    end

    test "returns nil for existing ref outside filter" do
      loader = Git::Ref::Loader.new(@repo, "default")
      assert_nil loader.qualified_ref("refs/special/case")

      loader = Git::Ref::Loader.new(@repo, "extended")
      assert_nil loader.qualified_ref("refs/__gh__/foobar")
    end

    test "does not hit GitRPC for subsequent requests" do
      loader = Git::Ref::Loader.new(@repo, "default")
      loader.qualified_ref("refs/heads/master")

      @repo.rpc.stubs(:read_qualified_refs).raises(RuntimeError.new("should not be called"))
      loader.qualified_ref("refs/heads/master")
    end
  end

  context "#qualified_refs" do
    test "returns existing refs within filter" do
      refnames = %w(refs/heads/master refs/tags/2.0-release)
      refs = Git::Ref::Loader.new(@repo, "default").qualified_refs(refnames)
      assert_equal refnames, refs.map(&:qualified_name)

      refnames = %w(refs/heads/master refs/special/case)
      refs = Git::Ref::Loader.new(@repo, "extended").qualified_refs(refnames)
      assert_equal refnames, refs.map(&:qualified_name)

      refnames = %w(refs/heads/master refs/__gh__/foobar)
      refs = Git::Ref::Loader.new(@repo).qualified_refs(refnames)
      assert_equal refnames, refs.map(&:qualified_name)
    end

    test "returns nil for non-existing refs" do
      assert_equal [nil], Git::Ref::Loader.new(@repo, "default").qualified_refs(%w(refs/heads/foobar))
    end

    test "returns nil for existing ref outside filter" do
      assert_equal [nil], Git::Ref::Loader.new(@repo, "default").qualified_refs(%w(refs/special/case))
      assert_equal [nil], Git::Ref::Loader.new(@repo, "extended").qualified_refs(%w(refs/__gh__/foobar))
    end

    test "does not hit GitRPC for subsequent requests" do
      loader = Git::Ref::Loader.new(@repo, "default")
      loader.qualified_refs(%w(refs/heads/master))

      @repo.rpc.stubs(:read_qualified_refs).raises(RuntimeError.new("should not be called"))
      loader.qualified_refs(%w(refs/heads/master))
    end

    test "does not attempt to load new refs over gitrpc if all refs are cached" do
      loader = Git::Ref::Loader.new(@repo, "default")
      loader.refs
      @repo.rpc.stubs(:read_qualified_refs).raises(RuntimeError.new("should not be called"))

      assert_nil loader.qualified_ref("refs/heads/does-not-exist")
    end

    test "returns refs in same order as requested" do
      refnames = %w(refs/heads/master refs/heads/foobar refs/tags/2.0-release)
      refs = Git::Ref::Loader.new(@repo, "default").qualified_refs(refnames)

      assert_equal 3, refs.size
      assert_equal "refs/heads/master", refs[0].qualified_name
      assert_nil refs[1]
      assert_equal "refs/tags/2.0-release", refs[2].qualified_name
    end
  end

  context "#refs" do
    test "returns existing refs within filter" do
      refs = Git::Ref::Loader.new(@repo, "default").refs

      assert_equal 7, refs.size
      refute_includes refs.map(&:qualified_name), "refs/special/case"
      refute_includes refs.map(&:qualified_name), "refs/__gh__/foobar"

      refs = Git::Ref::Loader.new(@repo, "extended").refs
      assert_equal 8, refs.size
      assert_includes refs.map(&:qualified_name), "refs/special/case"
      refute_includes refs.map(&:qualified_name), "refs/__gh__/foobar"

      refs = Git::Ref::Loader.new(@repo).refs
      assert_equal 9, refs.size
      assert_includes refs.map(&:qualified_name), "refs/special/case"
      assert_includes refs.map(&:qualified_name), "refs/__gh__/foobar"
    end

    test "does not hit GitRPC for subsequent requests" do
      loader = Git::Ref::Loader.new(@repo, "default")
      loader.refs

      @repo.rpc.stubs(:read_refs).raises(RuntimeError.new("should not be called"))
      loader.refs
    end
  end

  context "#refs_count" do
    test "returns number of refs ignoring filter" do
      assert_equal 9, Git::Ref::Loader.new(@repo, "default").refs_count
      assert_equal 9, Git::Ref::Loader.new(@repo, "extended").refs_count
      assert_equal 9, Git::Ref::Loader.new(@repo).refs_count
    end
  end

  context "#branches_count" do
    test "returns number of branches" do
      assert_equal 4, Git::Ref::Loader.new(@repo, "default").branches_count
      assert_equal 4, Git::Ref::Loader.new(@repo, "extended").branches_count
      assert_equal 4, Git::Ref::Loader.new(@repo).branches_count
    end
  end

  context "#tags_count" do
    test "returns number of tags" do
      assert_equal 3, Git::Ref::Loader.new(@repo, "default").tags_count
      assert_equal 3, Git::Ref::Loader.new(@repo, "extended").tags_count
      assert_equal 3, Git::Ref::Loader.new(@repo).tags_count
    end
  end

  context "#has_refs?" do
    test "returns true if there are refs" do
      assert_predicate Git::Ref::Loader.new(@repo, "default"), :has_refs?
    end

    test "returns false if there are no refs" do
      refute_predicate Git::Ref::Loader.new(@empty_repo, "default"), :has_refs?
    end
  end

  context "#has_branches?" do
    test "returns true if there are branches" do
      assert_predicate Git::Ref::Loader.new(@repo, "default"), :has_branches?
    end

    test "returns false if there are no branches" do
      refute_predicate Git::Ref::Loader.new(@empty_repo, "default"), :has_branches?
    end
  end

  context "#has_tags?" do
    test "returns true if there are tags" do
      assert_predicate Git::Ref::Loader.new(@repo, "default"), :has_tags?
    end

    test "returns false if there are no tags" do
      refute_predicate Git::Ref::Loader.new(@empty_repo, "default"), :has_tags?
    end
  end
end
