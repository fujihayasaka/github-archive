# typed: true
# frozen_string_literal: true

require "test_helper"

class GitRefUpdateTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, owner: create(:user), from_example: :pull_request_source)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  context "validation" do
    test "refname type must be String" do
      assert_raises(TypeError) do
        Git::Ref::Update.new(repository: @repo, refname: :master,
          before_oid: GitHub::NULL_OID, after_oid: GitHub::NULL_OID)
      end
    end

    test "commit oids need to be valid shas" do
      assert_raises(GitRPC::InvalidFullOid) do
        Git::Ref::Update.new(repository: @repo, refname: "refs/heads/master",
          before_oid: "abc", after_oid: "def")
      end
    end
  end

  context "Hash compliance" do
    test "instances are comparable" do
      one = Git::Ref::Update.new(repository: @repo, refname: "refs/heads/master",
        before_oid: GitHub::NULL_OID, after_oid: GitHub::NULL_OID)
      two = Git::Ref::Update.new(repository: @repo, refname: "refs/heads/master",
        before_oid: GitHub::NULL_OID, after_oid: GitHub::NULL_OID)

      assert_equal one, two

      three = Git::Ref::Update.new(repository: @repo, refname: "refs/heads/topic",
        before_oid: GitHub::NULL_OID, after_oid: GitHub::NULL_OID)

      refute_equal one, three
    end

    test "instances can be used as hash keys" do
      hash = Hash.new
      ref_update = Git::Ref::Update.new(repository: @repo, refname: "refs/heads/master",
        before_oid: GitHub::NULL_OID, after_oid: GitHub::NULL_OID)

      hash[ref_update] = :value

      assert_equal hash.keys, [ref_update]
      assert_equal hash[ref_update], :value
    end
  end

  context "#paths" do
    test "returns the paths that were changes in the update" do
      ref_update = Git::Ref::Update.new(repository: @repo, refname: "refs/heads/master",
          before_oid: "49bc45359806bb53b70aa558c0ee9371292924f8", after_oid: "a270ea0fdfba2bd5a33934e5184784cddce87f38")

      assert_same_elements %w[file11 file18], ref_update.paths
    end
  end

  context "#unqualified_refname" do
    test "returns the unqualified name of a branch" do
      ref_update = Git::Ref::Update.new(repository: @repo, refname: "refs/heads/master",
        before_oid: GitHub::NULL_OID, after_oid: GitHub::NULL_OID)

      assert_equal "master", ref_update.unqualified_refname
    end

    test "returns the unqualified name of a tag" do
      ref_update = Git::Ref::Update.new(repository: @repo, refname: "refs/tags/v1.0",
        before_oid: GitHub::NULL_OID, after_oid: GitHub::NULL_OID)

      assert_equal "v1.0", ref_update.unqualified_refname
    end

    test "returns the unqualified name of a custom ref" do
      ref_update = Git::Ref::Update.new(repository: @repo, refname: "refs/pulls/3125",
        before_oid: GitHub::NULL_OID, after_oid: GitHub::NULL_OID)

      assert_equal "3125", ref_update.unqualified_refname
    end

    test "returns the unqualified name of a ref with non UTF-8 characters" do
      ref_update = Git::Ref::Update.new(repository: @repo, refname: "refs/heads/test\xf1branch",
        before_oid: GitHub::NULL_OID, after_oid: GitHub::NULL_OID)

      assert_equal "test\xf1branch", ref_update.unqualified_refname
    end
  end

  test "loads branch commits" do
    ref_update = Git::Ref::Update.new(repository: @repo, refname: "refs/heads/master",
      before_oid: "49bc45359806bb53b70aa558c0ee9371292924f8", after_oid: "a270ea0fdfba2bd5a33934e5184784cddce87f38")

    assert_equal "49bc45359806bb53b70aa558c0ee9371292924f8", ref_update.before_commit.oid
    assert_equal "a270ea0fdfba2bd5a33934e5184784cddce87f38", ref_update.after_commit.oid
  end

  test "loads lightweight tag commits" do
    @repo.tags.build("lightweight").create("a270ea0fdfba2bd5a33934e5184784cddce87f38", @repo.owner)

    ref_update = Git::Ref::Update.new(repository: @repo, refname: "refs/tags/lightweight",
      before_oid: "49bc45359806bb53b70aa558c0ee9371292924f8", after_oid: "a270ea0fdfba2bd5a33934e5184784cddce87f38")

    assert_equal "49bc45359806bb53b70aa558c0ee9371292924f8", ref_update.before_commit.oid
    assert_equal "a270ea0fdfba2bd5a33934e5184784cddce87f38", ref_update.after_commit.oid
  end

  test "loads annotated tag commits" do
    tagger = {
      name: @repo.owner.git_author_name,
      email: @repo.owner.git_author_email,
      time: Time.zone.now,
    }

    tag_oid = @repo.rpc.create_tag_annotation("annotated", "a270ea0fdfba2bd5a33934e5184784cddce87f38", message: "Annotated", tagger:)

    ref_update = Git::Ref::Update.new(
      repository: @repo,
      refname: "refs/tags/annotated",
      before_oid: "49bc45359806bb53b70aa558c0ee9371292924f8",
      after_oid: tag_oid,
    )

    assert_equal "49bc45359806bb53b70aa558c0ee9371292924f8", ref_update.before_commit.oid
    assert_equal "a270ea0fdfba2bd5a33934e5184784cddce87f38", ref_update.after_commit.oid
    assert_equal ref_update.before_oid, ref_update.before_commit.oid
    assert_equal tag_oid, ref_update.after_oid
  end

  test "loads annotated tag commits for fast forwards (without changes)" do
    tagger = {
      name: @repo.owner.git_author_name,
      email: @repo.owner.git_author_email,
      time: Time.zone.now,
    }

    old_tag_oid = @repo.rpc.create_tag_annotation("annotated", "a270ea0fdfba2bd5a33934e5184784cddce87f38", message: "Annotated", tagger:)
    new_tag_oid = @repo.rpc.create_tag_annotation("annotated", "a270ea0fdfba2bd5a33934e5184784cddce87f38", message: "Annotated", tagger:)

    ref_update = Git::Ref::Update.new(
      repository: @repo,
      refname: "refs/tags/annotated",
      before_oid: old_tag_oid,
      after_oid: new_tag_oid,
      fast_forward: true,
    )

    assert_equal "a270ea0fdfba2bd5a33934e5184784cddce87f38", ref_update.before_commit.oid
    assert_equal "a270ea0fdfba2bd5a33934e5184784cddce87f38", ref_update.after_commit.oid
    assert_equal old_tag_oid, ref_update.before_oid
    assert_equal new_tag_oid, ref_update.after_oid
  end

  test "loads annotated tag commits for fast forwards (with changes)" do
    tagger = {
      name: @repo.owner.git_author_name,
      email: @repo.owner.git_author_email,
      time: Time.zone.now,
    }

    old_tag_oid = @repo.rpc.create_tag_annotation("annotated", "afae62531bd8c918f58116eba786a1385492a5d3", message: "Annotated", tagger:)
    new_tag_oid = @repo.rpc.create_tag_annotation("annotated", "a270ea0fdfba2bd5a33934e5184784cddce87f38", message: "Annotated", tagger:)

    ref_update = Git::Ref::Update.new(
      repository: @repo,
      refname: "refs/tags/annotated",
      before_oid: old_tag_oid,
      after_oid: new_tag_oid,
      fast_forward: true,
    )

    assert_equal "afae62531bd8c918f58116eba786a1385492a5d3", ref_update.before_commit.oid
    assert_equal "a270ea0fdfba2bd5a33934e5184784cddce87f38", ref_update.after_commit.oid
    assert_equal old_tag_oid, ref_update.before_oid
    assert_equal new_tag_oid, ref_update.after_oid
  end
end
