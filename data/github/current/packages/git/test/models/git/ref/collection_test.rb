# typed: true
# frozen_string_literal: true

require "test_helper"

class GitRefCollectionTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :simple)

    @empty_repo = create(:repository, from_example: :empty)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  context "#initialize" do
    test "allows passing prefix" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), prefix: "refs/tags/")
      assert_equal %w(v1 v2), collection.names
    end

    test "allows passing order" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), prefix: "refs/tags/", order: :desc)
      assert_equal %w(v2 v1), collection.names
    end

    test "allows passing branch sort flag" do
      Git::Ref.new(@repo, "refs/tags/aaa").create(@repo.default_oid, @repo.owner)
      Git::Ref.new(@repo, "refs/tags/1.0").create(@repo.default_oid, @repo.owner)
      Git::Ref.new(@repo, "refs/tags/2.0").create(@repo.default_oid, @repo.owner)
      Git::Ref.new(@repo, "refs/tags/zzz").create(@repo.default_oid, @repo.owner)

      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), prefix: "refs/tags/", branch_sort: true)
      assert_equal %w(1.0 2.0 aaa v1 v2 zzz), collection.names
    end
  end

  context "#find" do
    test "returns existing ref with qualified name" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      assert_equal "refs/heads/master", collection.find("refs/heads/master").qualified_name
    end

    test "returns existing ref with unqualified name" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      assert_equal "refs/heads/master", collection.find("master").qualified_name
    end

    test "returns nil for non-existing ref" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      assert_nil collection.find("foobar")
    end

    test "returns branch if branch and tag with same name exists" do
      Git::Ref.new(@repo, "refs/heads/same").create(@repo.default_oid, @repo.owner)
      Git::Ref.new(@repo, "refs/tags/same").create(@repo.default_oid, @repo.owner)

      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      assert_equal "refs/heads/same", collection.find("same").qualified_name
    end

    test "returns refs with prefix of collection" do
      Git::Ref.new(@repo, "refs/heads/foo/bar").create(@repo.default_oid, @repo.owner)

      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), prefix: "refs/heads/foo/")
      ref = collection.find("bar")

      refute_nil ref
      assert_equal "refs/heads/foo/bar", ref.qualified_name
      assert_equal "refs/heads/foo/", ref.prefix
      assert_equal "bar", ref.name
    end
  end

  context "#find_all" do
    test "returns all existing refs" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      refnames = %w(refs/tags/v1 refs/tags/v2)

      assert_equal refnames, collection.find_all(refnames).map(&:qualified_name)
    end

    test "returns refs with the same prefix" do
      Git::Ref.new(@repo, "refs/heads/foo/bar").create(@repo.default_oid, @repo.owner)

      collection = Git::Ref::Collection.new(
        loader: Git::Ref::Loader.new(@repo, "default"),
        prefix: "refs/heads/foo/",
      )

      ref = collection.find_all(["refs/heads/foo/bar"]).first
      refute_nil ref
      assert_equal "refs/heads/foo/bar", ref.qualified_name
      assert_equal "refs/heads/foo/", ref.prefix
      assert_equal "bar", ref.name
    end
  end

  context "#each" do
    test "allows to iterate over all refs" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), prefix: "refs/tags/")
      refnames = %w(refs/tags/v1 refs/tags/v2)

      collection.each.with_index do |ref, index|
        assert_equal refnames[index], ref.qualified_name
      end
    end

    test "returns refs with the same prefix" do
      Git::Ref.new(@repo, "refs/heads/foo/bar").create(@repo.default_oid, @repo.owner)

      collection = Git::Ref::Collection.new(
        loader: Git::Ref::Loader.new(@repo, "default"),
        prefix: "refs/heads/foo/",
      )

      ref = collection.to_a.first
      refute_nil ref
      assert_equal "refs/heads/foo/bar", ref.qualified_name
      assert_equal "refs/heads/foo/", ref.prefix
      assert_equal "bar", ref.name
    end
  end

  context "#names" do
    test "returns names of all refs" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), prefix: "refs/tags/")
      assert_equal %w(v1 v2), collection.names
    end
  end

  context "#read" do
    test "returns an existing ref" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), prefix: "refs/heads/")
      assert_equal "refs/heads/master", collection.read("master").qualified_name
    end

    test "returns an non-existing ref" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), prefix: "refs/heads/")
      assert_equal "refs/heads/foobar", collection.read("foobar").qualified_name
    end
  end

  context "#exist?" do
    test "returns true if ref exists (qualified name)" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      assert collection.exist?("refs/heads/master")
    end

    test "returns true if ref exists (unqualified name)" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      assert collection.exist?("master")
    end

    test "returns false if ref does not exist" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      refute collection.exist?("foobar")
    end
  end

  context "#build" do
    test "returns a ref" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), prefix: "refs/heads/")
      assert_equal "refs/heads/foobar", collection.build("foobar").qualified_name
    end
  end

  context "#find_or_build" do
    test "returns an existing ref" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      assert_equal "refs/heads/master", collection.find_or_build("master").qualified_name
    end

    test "returns a new ref" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), prefix: "refs/heads/")
      assert_equal "refs/heads/foobar", collection.find_or_build("foobar").qualified_name
    end
  end

  context "#create" do
    test "returns a newly-created ref" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), prefix: "refs/heads/")
      assert_equal "refs/heads/foobar", collection.create("foobar", @repo.default_oid, @repo.owner).qualified_name
    end
  end

  context "#size" do
    test "returns number of refs without prefix" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      assert_equal 5, collection.size
    end

    test "returns number of refs with heads or tags prefix" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), prefix: "refs/heads/")
      assert_equal 3, collection.size
    end
  end

  context "#any?" do
    test "returns true if there are any refs" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      assert_predicate collection, :any?
    end

    test "returns false if there are no refs" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@empty_repo, "default"))
      refute_predicate collection, :any?
    end
  end

  context "#empty?" do
    test "returns false if there are any refs" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      refute_predicate collection, :empty?
    end

    test "returns true if there are no refs" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@empty_repo, "default"))
      assert_predicate collection, :empty?
    end
  end

  context "#reverse!" do
    test "reverses order" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), order: :asc)

      assert_equal :asc, collection.order
      collection.reverse!
      assert_equal :desc, collection.order
    end
  end

  context "#filter" do
    test "returns new collection with pattern and order" do
      collection = Git::Ref::Collection.new(
        loader: Git::Ref::Loader.new(@repo, "default"),
        prefix: "refs/heads/",
        order: :asc,
      )

      filtered_collection = collection.filter("foobar", order: :desc)
      assert_equal "refs/heads/foobar", filtered_collection.prefix
      assert_equal :desc, filtered_collection.order
    end
  end

  context "#substring_filter" do
    test "returns filtered list of refs" do
      Git::Ref.new(@repo, "refs/tags/aaa").create(@repo.default_oid, @repo.owner)
      Git::Ref.new(@repo, "refs/tags/aaa-aa").create(@repo.default_oid, @repo.owner)
      Git::Ref.new(@repo, "refs/tags/bbb").create(@repo.default_oid, @repo.owner)

      collection = Git::Ref::Collection.new(
        loader: Git::Ref::Loader.new(@repo, "default"),
        prefix: "refs/tags/",
        order: :asc,
      )

      filtered_collection = collection.substring_filter(substring: "aaa", limit: 10)
      assert_equal %w[aaa aaa-aa], filtered_collection.map(&:name)

      filtered_collection = collection.substring_filter(substring: "aaa", limit: 1)
      assert_equal ["aaa"], filtered_collection.map(&:name)
    end

    test "handles utf-8 characters" do
      Git::Ref.new(@repo, "refs/tags/日本語").create(@repo.default_oid, @repo.owner)

      collection = Git::Ref::Collection.new(
        loader: Git::Ref::Loader.new(@repo, "default"),
        prefix: "refs/tags/",
        order: :asc,
      )

      filtered_collection = collection.substring_filter(substring: "日本語", limit: 10)
      assert_equal ["日本語".b], filtered_collection.map(&:name)
    end
  end

  context "#temp_name" do
    test "returns a non-existing ref name with given topic" do
      Git::Ref.new(@repo, "refs/heads/temp-1").create(@repo.default_oid, @repo.owner)
      Git::Ref.new(@repo, "refs/heads/patch-1").create(@repo.default_oid, @repo.owner)

      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))

      assert_equal "temp-2", collection.temp_name
      assert_equal "patch-2", collection.temp_name(topic: "patch")
      assert_equal "defunkt-patch-1", collection.temp_name(topic: "patch", prefix: "defunkt")
    end
  end

  context "#unqualified_name_conflict?" do
    test "returns true when branch and tag with same name exist" do
      Git::Ref.new(@repo, "refs/heads/same").create(@repo.default_oid, @repo.owner)
      Git::Ref.new(@repo, "refs/tags/same").create(@repo.default_oid, @repo.owner)

      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      assert collection.unqualified_name_conflict?("same")
    end

    test "returns false when branch and tag with same name do not exist" do
      Git::Ref.new(@repo, "refs/heads/same").create(@repo.default_oid, @repo.owner)

      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      refute collection.unqualified_name_conflict?("same")
    end
  end

  context "#unqualified_name_conflicts" do
    test "returns ref names when branch and tag with same name exist" do
      Git::Ref.new(@repo, "refs/heads/same1").create(@repo.default_oid, @repo.owner)
      Git::Ref.new(@repo, "refs/tags/same1").create(@repo.default_oid, @repo.owner)

      Git::Ref.new(@repo, "refs/heads/same2").create(@repo.default_oid, @repo.owner)
      Git::Ref.new(@repo, "refs/tags/same2").create(@repo.default_oid, @repo.owner)

      Git::Ref.new(@repo, "refs/heads/not-same1").create(@repo.default_oid, @repo.owner)
      Git::Ref.new(@repo, "refs/tags/not-same2").create(@repo.default_oid, @repo.owner)

      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      assert_equal %w[same1 same2], collection.unqualified_name_conflicts(%w[same1 same2 not-same1 not-same2])
      assert_equal ["same1"], collection.unqualified_name_conflicts(%w[same1 not-same2])
      assert_equal ["same2"], collection.unqualified_name_conflicts(%w[same2 not-same1])
    end

    test "returns nothing when branch and tag with same name do not exist" do
      Git::Ref.new(@repo, "refs/heads/same").create(@repo.default_oid, @repo.owner)

      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"))
      assert_empty collection.unqualified_name_conflicts(["same"])
      assert_empty collection.unqualified_name_conflicts(["not-same"])
      assert_empty collection.unqualified_name_conflicts([])
    end
  end

  context ".preload_target_objects" do
    test "loads target objects of all refs" do
      refs = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default")).to_a

      Git::Ref::Collection.preload_target_objects(refs)
      refs.each do |ref|
        assert_predicate ref, :target_acquired?
      end
    end
  end

  context ".qualify_tag_names" do
    test "returns qualified tag names" do
      input_tag_tames = ["tag1", "tag2", "tag3", nil, ""]
      assert_equal ["refs/tags/tag1", "refs/tags/tag2", "refs/tags/tag3"], Git::Ref::Collection.qualify_tag_names(input_tag_tames)
    end
  end
end
