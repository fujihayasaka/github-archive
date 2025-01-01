# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryObjectsCollectionTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :refs_test)
    @repo_bad = create(:repository, owner: @user)

    @commit_oid = "1d22e6fde59c9ded9b8093cf26213a5bd9d4c5ec"
    @tree_oid   = "ad0e5c6cda4b7e2e46cc45e42a72eab4aa2e8109"
    @blob_oid   = "fca94f84afd7d749c62626011f972a509f6a5ac6"
    @tag_oid    = "02a2cfc6b8fcecfa7f045bdc014eb2ae7191fb2d"
    @bad_oid    = "9999999999999999999999999999999999999999"

    enable_cache_storage
  end

  setup do
    reset_cache
    @objects = RepositoryObjectsCollection.new(@repo)
  end

  test "read single git object" do
    assert object = @objects.read(@commit_oid)
    assert_equal @commit_oid, object.oid
    assert object.is_a?(Commit)
  end

  test "read a single bad object" do
    assert_raises(GitRPC::ObjectMissing) do
      @objects.read(@bad_oid)
    end
  end

  test "read a single object with the wrong type" do
    assert_raises(GitRPC::InvalidObject) do
      @objects.read(@commit_oid, "tag")
    end
  end

  test "read git objects in batch" do
    oids = [@commit_oid, @tree_oid, @blob_oid, @tag_oid]
    objects = @objects.read(oids)
    assert_equal oids.size, objects.size
    oids.zip(objects).each do |oid, object|
      assert_equal oid, object.oid
    end
  end

  test "read git objects in batch with duplicates" do
    oids = [@commit_oid, @tree_oid, @blob_oid, @tag_oid]
    oids += oids
    objects = @objects.read(oids)
    assert_equal oids.size, objects.size
    oids.zip(objects).each do |oid, object|
      assert_equal oid, object.oid
    end
  end

  test "read bad objects in batch" do
    assert_raises(GitRPC::ObjectMissing) do
      @objects.read([@tree_oid, @bad_oid])
    end
  end

  test "read objects with the wrong type in batch" do
    assert_raises(GitRPC::InvalidObject) do
      @objects.read([@tree_oid, @commit_oid, @blob_oid], "tree")
    end
  end

  test "read commit object" do
    commit = @objects.read(@commit_oid)
    assert commit.is_a?(Commit)
    assert_equal @commit_oid, commit.oid
  end

  test "read tag object" do
    tag = @objects.read(@tag_oid)
    assert tag.is_a?(Tag)
    assert_equal @tag_oid, tag.oid
  end

  test "read tree object" do
    tree = @objects.read(@tree_oid)
    assert tree.is_a?(Tree)
    assert_equal @tree_oid, tree.oid
  end

  test "read blob object" do
    blob = @objects.read(@blob_oid)
    assert blob.is_a?(Blob)
    assert_equal @blob_oid, blob.oid
  end

  test "checking if a single object exists" do
    assert @objects.exist?(@commit_oid)
    assert !@objects.exist?(@bad_oid)
  end

  test "checking if multiple objects exists" do
    assert @objects.exist?([@commit_oid, @tree_oid, @blob_oid, @tag_oid])
    assert !@objects.exist?([@commit_oid, @bad_oid, @tree_oid, @blob_oid, @tag_oid])
  end

  test "oid verificaton" do
    assert_raises(RepositoryObjectsCollection::InvalidObjectId) { @objects.read(["master"]) }
    assert_raises(RepositoryObjectsCollection::InvalidObjectId) { @objects.read("deadbee") }
    assert_raises(RepositoryObjectsCollection::InvalidObjectId) { @objects.read(nil) }
    assert_raises(RepositoryObjectsCollection::InvalidObjectId) { @objects.read([nil]) }
    assert_raises(RepositoryObjectsCollection::InvalidObjectId) { @objects.read([{}]) }
  end
end
