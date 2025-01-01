# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class UploadManifestTest < GitHub::TestCase
  self.use_transactional_tests = false

  fixtures do
    @owner = create(:user)
    @rando = create(:user)
    @repo = create(:repository, owner: @owner, from_example: :simple)
  end

  setup do
    Spokesd.enable_spokesd
    @manifest = UploadManifest.create(repository: @repo, uploader: @owner)
    @one = @manifest.files.create(
      repository: @repo,
      uploader: @owner,
      name: "test1.txt",
      content_type: "text/plain",
      size: 3,
      state: 1) # uploaded
    @two = @manifest.files.create(
      repository: @repo,
      uploader: @owner,
      directory: "test directory/sub directory",
      name: "test2.txt",
      content_type: "text/plain",
      size: 4,
      state: 1) # uploaded
    @manifest.update(state: 1) # uploaded

    WebFlowHelper.setup_webflow
  end

  test "requires repository and uploader" do
    subject = UploadManifest.create(
      repository: @repo,
      uploader: @owner)

    refute subject.new_record?
    assert subject.valid?
  end

  test "uploader must have push access to repository" do
    subject = UploadManifest.create(
      repository: @repo,
      uploader: @rando)

    assert subject.new_record?
    refute subject.valid?
  end

  test "rejects long directory" do
    # directory that has fewer than 1024 characters, but too many bytes
    testdir = "\u043B" * 1000
    @manifest.directory = testdir
    refute @manifest.valid?
    refute @manifest.errors[:directory].empty?
  end

  test "rejects directory navigation characters" do
    @manifest.directory = "/../../../"
    refute @manifest.valid?
    refute @manifest.errors[:directory].empty?
  end

  test "removes extra directory separators" do
    subject = UploadManifest.new(
      repository: @repo,
      directory: "/a/b//c/")
    assert_equal "a/b/c", subject.directory
  end

  test "marks itself as failed" do
    assert_predicate @manifest, :state_uploaded?

    @manifest.state_failed!

    assert_predicate @manifest, :state_failed?
  end

  test "stores files in a single git commit" do
    skip "fails intermittently: https://github.com/github/github/issues/48043" if ENV["GITHUB_CI"]

    stub_request(:get, %r{/#{@repo.id}/#{@one.id}}).to_return(body: SecureRandom.uuid)
    stub_request(:get, %r{/#{@repo.id}/#{@two.id}}).to_return(body: SecureRandom.uuid + "b")

    assert_nil @manifest.commit_oid
    old_tip = @repo.spokes_api.resolve_object(object_name: "refs/heads/master")

    @manifest.commit

    # Refresh oids.
    @one.reload
    @two.reload

    # Tracked oids in database.
    assert_predicate @manifest, :state_committed?
    refute_nil @manifest.commit_oid

    # Moved master ref to our commit oid.
    new_tip = @repo.spokes_api.resolve_object(object_name: "refs/heads/master")
    refute_equal new_tip, old_tip
    assert_equal new_tip, @manifest.commit_oid

    # Commit is well formed.
    commit = @repo.rpc.read_commits([@manifest.commit_oid]).first
    assert_equal old_tip, commit["parents"].first
    assert_equal @owner.git_author_name, commit["author"].first
    assert_equal @owner.git_author_email, commit["author"].second
    refute_nil commit["message"]

    # Both blobs in single commit.
    test1 = @repo.rpc.read_tree_entry(@manifest.commit_oid, "test1.txt")
    test2 = @repo.rpc.read_tree_entry(@manifest.commit_oid, "test directory/sub directory/test2.txt")

    assert_equal 36, test1["size"]
    assert_equal 37, test2["size"]

    # Cleaned up temporary ref.
    assert_nil @repo.spokes_api.resolve_object(object_name: "refs/__gh__/temp/upload-manifest/#{@manifest.id}-#{@manifest.created_at.to_i}")
  end

  test "stores files in a single git commit including a gitattributes file" do
    @manifest.update(state: 0)
    three = @manifest.files.create(
      repository: @repo,
      uploader: @owner,
      name: ".gitattributes",
      content_type: "text/plain",
      size: 4,
      state: 1 # uploaded
    )
    @manifest.update(state: 1)

    stub_request(:get, %r{/#{@repo.id}/#{@one.id}}).to_return(body: SecureRandom.uuid)
    stub_request(:get, %r{/#{@repo.id}/#{@two.id}}).to_return(body: SecureRandom.uuid + "b")
    stub_request(:get, %r{/#{@repo.id}/#{three.id}}).to_return(body: SecureRandom.uuid + "bc")

    assert_nil @manifest.commit_oid
    old_tip = @repo.spokes_api.resolve_object(object_name: "refs/heads/master")

    @manifest.commit

    # Refresh oids.
    @one.reload
    @two.reload
    three.reload

    # Tracked oids in database.
    assert_predicate @manifest, :state_committed?
    refute_nil @manifest.commit_oid

    # Moved master ref to our commit oid.
    new_tip = @repo.spokes_api.resolve_object(object_name: "refs/heads/master")
    refute_equal new_tip, old_tip
    assert_equal new_tip, @manifest.commit_oid

    # Commit is well formed.
    commit = @repo.rpc.read_commits([@manifest.commit_oid]).first
    assert_equal old_tip, commit["parents"].first
    assert_equal @owner.git_author_name, commit["author"].first
    assert_equal @owner.git_author_email, commit["author"].second
    refute_nil commit["message"]

    # All blobs in single commit.
    assert_equal 36, @repo.rpc.read_tree_entry(@manifest.commit_oid, "test1.txt")["size"]
    assert_equal 37, @repo.rpc.read_tree_entry(@manifest.commit_oid, "test directory/sub directory/test2.txt")["size"]
    assert_equal 38,  @repo.rpc.read_tree_entry(@manifest.commit_oid, ".gitattributes")["size"]

    # Cleaned up temporary ref.
    assert_nil @repo.spokes_api.resolve_object(object_name: "refs/__gh__/temp/upload-manifest/#{@manifest.id}-#{@manifest.created_at.to_i}")
  end

  test "commits to non-master branch" do
    @manifest.update(branch: "hubot-upload-1")

    stub_request(:get, %r{/#{@repo.id}/#{@one.id}}).to_return(body: "abc")
    stub_request(:get, %r{/#{@repo.id}/#{@two.id}}).to_return(body: "defg")

    master_oid = @repo.spokes_api.resolve_object(object_name: "refs/heads/master")

    @manifest.commit

    # Moved ref to our commit oid.
    new_tip = @repo.spokes_api.resolve_object(object_name: "refs/heads/hubot-upload-1")
    refute_equal new_tip, master_oid
    assert_equal new_tip, @manifest.commit_oid

    # Branched from latest master oid.
    assert_equal master_oid, @repo.rpc.read_commits([new_tip]).first["parents"].first

    # Leave master alone.
    assert_equal master_oid, @repo.spokes_api.resolve_object(object_name: "refs/heads/master")

    # Cleaned up temporary ref.
    assert_nil @repo.spokes_api.resolve_object(object_name: "refs/__gh__/temp/upload-manifest/#{@manifest.id}-#{@manifest.created_at.to_i}")
  end

  test "prevents commits to protected branches" do
    @repo.protect_branch("master", creator: @owner, required_status_checks: { contexts: %w[ci/janky], include_admins: true }, entry_point: :test_case)

    stub_request(:get, %r{/#{@repo.id}/#{@one.id}}).to_return(body: "abc")
    stub_request(:get, %r{/#{@repo.id}/#{@two.id}}).to_return(body: "defg")

    master_oid = @repo.spokes_api.resolve_object(object_name: "refs/heads/master")

    # Exception should bubble out to job.
    assert_raises(Git::Ref::ProtectedBranchUpdateError) do
      @manifest.commit
    end

    # Manifest not committed and still in :uploaded state.
    assert_nil @manifest.commit_oid
    assert_predicate @manifest, :state_uploaded?

    # Leave master alone.
    assert_equal master_oid, @repo.spokes_api.resolve_object(object_name: "refs/heads/master")
  end

  test "prevents commits after user lost push access" do
    manifest = UploadManifest.create(repository: @repo, uploader: @rando, state: 1)

    master_oid = @repo.spokes_api.resolve_object(object_name: "refs/heads/master")

    manifest.commit

    # Manifest not committed and still in :uploaded state.
    assert_nil manifest.commit_oid
    assert_predicate manifest, :state_uploaded?

    # Leave master alone.
    assert_equal master_oid, @repo.spokes_api.resolve_object(object_name: "refs/heads/master")
  end

  test "#schedule_commit enqueues a job to commit the upload manifest" do
    @manifest.schedule_commit("master", "awesome file", false)
    arg_matcher = -> ((manifest_id, _status_id)) { @manifest.id == manifest_id }
    assert_enqueued_with(job: CommitUploadManifestJob, args: arg_matcher)
  end

  test "signs commits" do
    stub_request(:get, %r{/#{@repo.id}/#{@one.id}}).to_return(body: "abc")
    stub_request(:get, %r{/#{@repo.id}/#{@two.id}}).to_return(body: "defg")

    @manifest.commit
    commit = @repo.commits.find(@manifest.commit_oid)
    assert_predicate commit, :verified_signature?
  end if GitHub.web_commit_signing_enabled?
end
