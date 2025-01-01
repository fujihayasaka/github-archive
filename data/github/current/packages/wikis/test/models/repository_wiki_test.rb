# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryWikiTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
    @wiki = @repo.unsullied_wiki
  end

  def assert_no_new_replica_and_checksum_rows(network_id, repo_id)
    rr_before = ::DGit.get_repo_replica_ids(network_id, repo_id).length
    rc_before = ::DGit.get_repo_replica_checksums(network_id, repo_id).length
    yield
    assert_equal rr_before, ::DGit.get_repo_replica_ids(network_id, repo_id).length
    assert_equal rc_before, ::DGit.get_repo_replica_checksums(network_id, repo_id).length
  end

  test "cache_version_number defaults to 1" do
    assert_nil RepositoryWiki.find_by(repository: @repo)

    @repo.initialize_wiki(@user)
    @repo.reload

    refute_nil RepositoryWiki.find_by(repository: @repo)
    assert_equal 1, RepositoryWiki.find_by!(repository: @repo).cache_version_number
  end

  test "cache_version_number increments on update" do
    @repo.initialize_wiki(@user)
    @repo.reload
    assert_equal 1, RepositoryWiki.find_by!(repository: @repo).cache_version_number

    @wiki.pages.create("home", :markdown, "new", "initial commit", @repo.owner)

    assert RepositoryWiki.find_by!(repository: @repo).cache_version_number > 1
  end

  if GitHub.email_verification_enabled?
    test "unverified user cannot create wiki" do
      User.any_instance.expects(:must_verify_email?).returns(true)
      assert_nil RepositoryWiki.find_by(repository: @repo)
      @repo.initialize_wiki(@user)
      assert_nil RepositoryWiki.find_by(repository: @repo)
    end
  end

  context "#initialize_wiki" do
    test "creates a repository_wiki and initializes a repo" do
      refute @repo.unsullied_wiki.exist?
      assert_difference "RepositoryWiki.count", 1 do
        @repo.initialize_wiki(@user)
      end

      assert @repo.unsullied_wiki.exist?
    end

    test "does not create a repository_wiki when disk repo creation fails" do
      GitRPC::Client.any_instance.stubs(:ensure_initialized).raises(GitRPC::Error)
      assert_no_difference "RepositoryWiki.count" do
        assert_raises(GitRPC::Error) { @repo.initialize_wiki(@user) }
      end
    end

    test "does not create a repository_wiki when spokes fails" do
      GitRPC::Client.any_instance.stubs(:ensure_initialized).raises(GitHub::DGit::Error)
      assert_no_difference "RepositoryWiki.count" do
        assert_raises(GitHub::DGit::Error) { @repo.initialize_wiki(@user) }
      end
    end

    test "does not create disk repo when repository_wiki insertion fails" do
      RepositoryWiki.stubs(:create!).raises(ActiveRecord::ActiveRecordError.new)
      assert_no_new_replica_and_checksum_rows(@repo.network_id, @repo.id) do
        assert_raises(ActiveRecord::ActiveRecordError) { @repo.initialize_wiki(@user) }
      end
      assert_raises(GitHub::DGit::UnroutedError) { @repo.unsullied_wiki.rpc.exist? }
    end

    test "uses an existing repository wiki if it is present" do
      RepositoryWiki.create!(repository_id: @repo.id)
      refute @repo.unsullied_wiki.exist?

      assert_no_difference "RepositoryWiki.count" do
        @repo.initialize_wiki(@user)
      end

      assert @repo.unsullied_wiki.exist?
    end

    test "destroys the existing repository_wiki if repo creation fails and the wiki does not exist" do
      RepositoryWiki.create!(repository_id: @repo.id)
      refute @repo.unsullied_wiki.exist?

      GitRPC::Client.any_instance.stubs(:ensure_initialized).raises(GitRPC::Error)

      assert_difference("RepositoryWiki.count", -1) do
        assert_raises(GitRPC::Error) { @repo.initialize_wiki(@user) }
      end

      refute @repo.unsullied_wiki.exist?
    end

    test "is idempotent" do
      @repo.initialize_wiki(@user)

      GitRPC::Client.any_instance.expects(:ensure_initialized).never
      assert_no_difference "RepositoryWiki.count" do
        assert_no_new_replica_and_checksum_rows(@repo.network_id, @repo.id) do
          @repo.initialize_wiki(@user)
        end
      end
    end
  end

  test "deletes on repository soft-delete" do
    private_repo = create(:private_repository)
    example_repo :simple, @repo.unsullied_wiki, private_repo.unsullied_wiki

    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

    wiki1 = RepositoryWiki.where(repository_id: private_repo.id).first
    wiki2 = RepositoryWiki.where(repository_id: @repo.id).first

    @repo.remove(@user, synchronous: true)

    assert_equal wiki1, RepositoryWiki.find_by(id: T.must(wiki1).id)
    assert_nil  Repositories::Public.find_active(@repo.id)
  end
end
