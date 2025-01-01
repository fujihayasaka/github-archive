# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryArchiveCommandTest < GitHub::TestCase
  fixtures do
    Spokesd.enable_spokesd

    user = create :user, login: "fern-kunde"
    @repo = create :repository, description: "boom", name: "Kunde-Smith", owner: user

    contents = [{ name: "file1.txt", value: "cool" }]
    @gist = GistHelpers.generate(contents: contents, user: user)
  end

  test "separates legacy from new archives" do
    assert_kind_of GitRepository::ArchiveCommand,
      @repo.archive_command("master", "zip")

    assert_kind_of GitRepository::ArchiveCommand,
      @repo.archive_command("master", "tar.gz")

    assert_kind_of GitRepository::LegacyArchiveCommand,
      @repo.archive_command("master", "legacy.zip")

    assert_kind_of GitRepository::LegacyArchiveCommand,
      @repo.archive_command("master", "legacy.tar.gz")
  end

  test "generates a Hash for the site/archive api" do
    example_repo :archive, @repo
    arc = @repo.archive_command "master", "zip"
    hash = arc.to_hash
    assert_equal({
      type: "zip", mime_type: "application/zip",
      file: arc.filename,
      prefix: arc.prefix, commit: arc.commit_oid,
      repo: @repo.id, commitish: "master" },
      hash.slice(:type, :mime_type, :file, :prefix, :commit, :repo, :commitish))
    assert_equal({ route: @repo.route, path: @repo.shard_path }, hash.slice(:route, :path))
    assert_equal({ route: @repo.route, path: @repo.shard_path }, hash.fetch(:routes).first)
    assert_equal(GitHub.dgit_default_copies, hash.fetch(:routes).size, "number of routes")
  end

  context "token_scope" do
    test "returns nil if git repository is nil" do
      refute GitRepository::ArchiveCommand.token_scope(nil)
    end

    test "returns a formatted scope for a repository" do
      assert_equal "Repository:Archive:#{@repo.token_scope}",
                  GitRepository::ArchiveCommand.token_scope(@repo)
    end

    test "returns a formatted scope for a gist" do
      assert_equal "Gist:Archive:#{@gist.token_scope}",
                  GitRepository::ArchiveCommand.token_scope(@gist)
    end
  end

  context "new archive commands" do
    test "generates zip archive command" do
      example_repo :archive, @repo
      arc = @repo.archive_command "master", "zip"

      assert arc.archivable?
    end

    test "generates tar.gz archive command" do
      example_repo :archive, @repo
      arc = @repo.archive_command "master", "tar.gz"

      assert arc.archivable?
    end

    test "gets commit from tree sha" do
      example_repo :archive, @repo
      arc = @repo.archive_command "master", "zip"

      assert arc.archivable?
      assert_equal "d97fb1d52f8257dae581271b249892e654e2fd02",
        arc.commit_oid
      assert_equal "543b9bebdc6bd5c4b22136034a95dd097a57d3dd",
        arc.treeish_oid
      assert_equal "Kunde-Smith-master", arc.prefix
    end

    test "gets empty treeish from tagged blob" do
      example_repo :archive, @repo
      arc = @repo.archive_command "tagged-blob", "zip"

      refute arc.archivable?
      assert_equal "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391",
        arc.commit_oid
      assert_nil arc.treeish_oid
      assert_equal "Kunde-Smith-tagged-blob", arc.prefix
    end

    test "gets commit from custom branch" do
      example_repo :archive, @repo
      arc = @repo.archive_command "other", "zip"

      assert arc.archivable?
      assert_equal "859b2de82a9eaceb8fcd4f9b66ccb1c98edca4ca",
        arc.commit_oid
      assert_equal "21a7d70e0b6d7db6a57159723500c1d74a79273f",
        arc.treeish_oid
      assert_equal "Kunde-Smith-other", arc.prefix
    end

    test "gets commit from custom tag" do
      example_repo :archive, @repo
      arc = @repo.archive_command "booya", "tar.gz"

      assert arc.archivable?
      assert_equal "859b2de82a9eaceb8fcd4f9b66ccb1c98edca4ca",
        arc.commit_oid
      assert_equal "21a7d70e0b6d7db6a57159723500c1d74a79273f",
        arc.treeish_oid
      assert_equal "Kunde-Smith-booya", arc.prefix
    end

    test "gets commit from annotated tag" do
      example_repo :archive, @repo
      arc = @repo.archive_command "v1.0", "tar.gz"

      assert arc.archivable?
      assert_equal "006d73e24494a411c3fd726b24c660d52b5e3194",
        arc.commit_oid
      assert_equal "542f05aa2361e3532bc6a7be55a06f0d9ba80013",
        arc.treeish_oid
      assert_equal "Kunde-Smith-1.0", arc.prefix
    end

    test "gets commit from nested annotated tag" do
      example_repo :archive, @repo
      arc = @repo.archive_command "v1.0.0", "tar.gz"

      assert arc.archivable?
      assert_equal "006d73e24494a411c3fd726b24c660d52b5e3194",
        arc.commit_oid
      assert_equal "542f05aa2361e3532bc6a7be55a06f0d9ba80013",
        arc.treeish_oid
      assert_equal "Kunde-Smith-1.0.0", arc.prefix
    end

    test "is not archivable when the commit is not on a branch or tag" do
      skip "temporarily skipping; want to check performance on reachability checks"
      branch = "temp_test_branch"
      tag    = "temp_test_tag"

      example_repo :archive, @repo

      ref      = @repo.heads.create(branch, @repo.heads.find("master").target_oid, @repo.owner)
      metadata = { message: "test commit", committer: @repo.owner }
      commit   = ref.append_commit(metadata, @repo.owner) {}

      arc = @repo.archive_command(commit.oid, "tar.gz")
      assert arc.archivable?
      assert_equal commit.oid, arc.commit_oid

      ref.delete(@repo.owner)
      arc = @repo.archive_command(commit.oid, "tar.gz")
      refute arc.archivable?

      ref = @repo.tags.create(tag, commit.oid, @repo.owner)

      arc = @repo.archive_command(commit.oid, "tar.gz")
      assert arc.archivable?
      assert_equal commit.oid, arc.commit_oid

      ref.delete(@repo.owner)
      arc = @repo.archive_command(commit.oid, "tar.gz")
      refute arc.archivable?

      ref = @repo.extended_refs.create("refs/whatever", commit.oid, @repo.owner)

      arc = @repo.archive_command(commit.oid, "tar.gz")
      refute arc.archivable?

      ref.delete(@repo.owner)
    end

    test "builds prefix for version tag in public repo" do
      example_repo :simple_tags_repository_test, @repo
      @repo.public = true
      arc = @repo.archive_command "v1", "zip"
      assert_equal "Kunde-Smith-1", arc.prefix
    end

    test "builds download filename for public repo" do
      example_repo :simple_tags_repository_test, @repo
      @repo.public = true
      arc = @repo.archive_command "v1", "zip"
      assert_equal "Kunde-Smith-1.zip", arc.filename
    end

    test "fails to build download filename for public repo with invalid revision" do
      example_repo :simple_tags_repository_test, @repo
      @repo.public = true
      arc = @repo.archive_command "bogus revision", "zip"
      assert_nil arc.commit_oid
    end

    test "builds download filename for private repo" do
      example_repo :simple_tags_repository_test, @repo
      @repo.public = false
      arc = @repo.archive_command "v1", "zip"

      assert_equal "Kunde-Smith-1.zip", arc.filename
    end
  end

  context "legacy archive commands" do
    test "generates zip archive command (legacy)" do
      example_repo :archive, @repo
      arc = @repo.archive_command "master", "legacy.zip"

      assert arc.archivable?
    end

    test "gets commit from tree sha (legacy)" do
      example_repo :archive, @repo
      arc = @repo.archive_command "master", "legacy.zip"

      assert arc.archivable?
      assert_equal "d97fb1d52f8257dae581271b249892e654e2fd02",
        arc.commit_oid
      assert_equal "543b9bebdc6bd5c4b22136034a95dd097a57d3dd",
        arc.treeish_oid
      assert_equal "fern-kunde-Kunde-Smith-d97fb1d", arc.prefix
    end

    test "gets commit from custom branch (legacy)" do
      example_repo :archive, @repo
      arc = @repo.archive_command "other", "legacy.zip"

      assert arc.archivable?
      assert_equal "859b2de82a9eaceb8fcd4f9b66ccb1c98edca4ca",
        arc.commit_oid
      assert_equal "21a7d70e0b6d7db6a57159723500c1d74a79273f",
        arc.treeish_oid
      assert_equal "fern-kunde-Kunde-Smith-859b2de", arc.prefix
      assert_equal "other-859b2de", arc.fallback_tag_name
    end

    test "gets commit from custom tag (legacy)" do
      example_repo :archive, @repo
      arc = @repo.archive_command "booya", "legacy.tar.gz"

      assert arc.archivable?
      assert_equal "859b2de82a9eaceb8fcd4f9b66ccb1c98edca4ca",
        arc.commit_oid
      assert_equal "21a7d70e0b6d7db6a57159723500c1d74a79273f",
        arc.treeish_oid
      assert_equal "fern-kunde-Kunde-Smith-9afa7a9", arc.prefix
      assert_equal "booya-859b2de", arc.fallback_tag_name
    end

    test "gets empty treeish from tagged-blob (legacy)" do
      example_repo :archive, @repo
      arc = @repo.archive_command "tagged-blob", "legacy.tar.gz"

      refute arc.archivable?
      assert_equal "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391",
        arc.commit_oid
      assert_nil arc.treeish_oid
      assert_equal "fern-kunde-Kunde-Smith-730dba5", arc.prefix
      assert_equal "tagged-blob-e69de29", arc.fallback_tag_name
    end

    test "gets commit from annotated tag (legacy)" do
      example_repo :archive, @repo
      arc = @repo.archive_command "v1.0", "legacy.tar.gz"

      assert arc.archivable?
      assert_equal "006d73e24494a411c3fd726b24c660d52b5e3194",
        arc.commit_oid
      assert_equal "fern-kunde-Kunde-Smith-65e5695", arc.prefix
    end

    test "gets commit from nested annotated tag (legacy)" do
      example_repo :archive, @repo
      arc = @repo.archive_command "v1.0.0", "legacy.tar.gz"

      assert arc.archivable?
      assert_equal "006d73e24494a411c3fd726b24c660d52b5e3194",
        arc.commit_oid
      assert_equal "542f05aa2361e3532bc6a7be55a06f0d9ba80013",
        arc.treeish_oid
      assert_equal "fern-kunde-Kunde-Smith-006d73e", arc.prefix
    end

    test "builds recent_tag_name for public repo (legacy)" do
      example_repo :simple_tags_repository_test, @repo
      @repo.public = true
      arc = @repo.archive_command "v1", "legacy.zip"
      assert_equal "v1-0-gc180049", arc.recent_tag_name
    end

    test "builds download filename for public repo" do
      example_repo :simple_tags_repository_test, @repo
      @repo.public = true
      arc = @repo.archive_command "v1", "legacy.zip"
      assert_equal "fern-kunde-Kunde-Smith-v1-0-gc180049.zip", arc.filename
    end

    test "fails to build download filename for public repo with invalid revision (legacy)" do
      example_repo :simple_tags_repository_test, @repo
      @repo.public = true
      arc = @repo.archive_command "a bad revision", "legacy.zip"
      assert_nil arc.commit_oid
    end

    test "builds download filename with slash for public repo" do
      example_repo :simple_tags_repository_test, @repo
      @repo.public = true
      arc = @repo.archive_command "v1", "legacy.zip"
      arc.stubs(:recent_tag_name).returns("v1/a-0-gc180049")

      assert_equal "fern-kunde-Kunde-Smith-v1-a-0-gc180049.zip", arc.filename
    end

    test "builds recent_tag_name for private repo" do
      example_repo :simple_tags_repository_test, @repo
      @repo.public = false
      arc = @repo.archive_command "v1", "legacy.zip"
      assert_equal "v1-0-gc1800491d95c42b4e96fb83f31fe8d9230c62907", arc.recent_tag_name
    end

    test "builds download filename for private repo" do
      example_repo :simple_tags_repository_test, @repo
      @repo.public = false
      arc = @repo.archive_command "v1", "legacy.zip"

      assert_equal "fern-kunde-Kunde-Smith-v1-0-gc1800491d95c42b4e96fb83f31fe8d9230c62907.zip", arc.filename
    end

    test "converts invalid shell values" do
      arc = @repo.archive_command "master", "legacy.zip"
      arc.stubs(:recent_tag_name).returns("1-2_3-[]-a-|-b-()-c")

      assert_equal "1-2_3-a-b-c", arc.tag
    end

    test "recent_tag_name timeout" do
      example_repo :simple_tags_repository_test, @repo
      @repo.public = true

      arc = @repo.archive_command "v1", "legacy.zip"
      assert_equal "v1-0-gc180049", arc.recent_tag_name

      GitRPC::Client.any_instance.stubs(:describe).raises(GitRPC::Timeout)
      arc = @repo.archive_command "v1", "legacy.zip"
      assert_nil arc.recent_tag_name
    end
  end
end
