# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::Domain::CommitsTest < GitHub::TestCase
  include HydroTestHelpers
  Spokesd.share_spokesdb(self)

  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner, from_example: :branch_and_tag_refs)
    @repo2 = create(:repository, owner: @owner, from_example: :simple)
    @commits_test_repo = create(:repository, owner: @owner, from_example: :commit_test)

    @author_email = "monalisa@github.com"
    @author_name = "Mona Lisa"
    @time_zone = @owner.time_zone.freeze
    @title = "Commit title"
    @message = "This is a good message."

    commit_time ||= Time.current
    @web_commit_data = {
      "author" => {
        "email" => @author_email,
        "name"  => @author_name,
        "time"  => commit_time.in_time_zone(@time_zone).iso8601,
      },
      "committer" => {
        "email" => GitHub.web_committer_email,
        "name"  => GitHub.web_committer_name,
        "time"  => commit_time.iso8601,
      },
      "message" => "#{@title}\n\n#{@message}",
    }

    @committer = create(:user, email: "technoweenie@gmail.com", name: "technoweenie")
    @commits_test_oid = "3572d83ba062076f6a740379463d0f3f770d7fc5"
    @commits_test_info = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
    }
  end

  setup do
    Spokesd.enable_spokesd

    example_repo :branch_and_tag_refs, @repo
    example_repo :simple, @repo2
    example_repo :commit_test, @commits_test_repo

    master = @repo.refs.find("master")
    @repo.refs.find("other").append_commit({
      message: "A commit to topic branch",
      committer: @owner,
    }, @owner) do |files|
      files.add("file1.txt", "Contents of the file")
    end

    @repo.refs.find("other").append_commit({
      message: "Another commit to topic branch",
      committer: @owner,
    }, @owner) do |files|
      files.add("file2.txt", "Different file contents")
    end

    @merge_commit, _, _ = @repo.commits.create_merge_commit(
      @owner,
      master.target_oid,
      @repo.refs.find("other").target_oid
    )

    master = @repo2.refs.find("master")
    @first_commit = master.append_commit({
      message: "A commit to master",
      committer: @owner,
    }, @owner) do |files|
      files.add("file1.txt", "Contents of the file")
    end

    @second_commit = master.append_commit({
      message: "Second commit to master",
      committer: @owner,
    }, @owner) do |files|
      files.add("file2.txt", "Contents of the file")
    end

    @third_commit = master.append_commit({
      message: "Third commit to master",
      committer: @owner,
    }, @owner) do |files|
      files.add("file3.txt", "Contents of the file")
    end

    reset_hydro # Flush any messages from the lines above
  end

  sig { returns(Repositories::Domain::Commits) }
  def domain
    Repositories.domain.commits
  end

  context "by_oid" do
    test "find a single commit" do
      [@commits_test_oid, @commits_test_oid.upcase].each do |oid|
        commit = T.must(domain.by_oid(repository: @commits_test_repo, commit_oid: oid))
        assert_equal @commits_test_oid, commit.oid
        assert_equal @commits_test_info["parents"], commit.parent_oids
        assert_equal @commits_test_info["tree"], commit.tree_oid
        assert_equal @commits_test_info["message"], commit.message
        assert_equal @commits_test_info["author"][0], commit.author_name
        assert_equal @commits_test_info["author"][1], commit.author_email
        assert_equal Time.iso8601(@commits_test_info["author"][2]), commit.authored_date
        assert_equal @commits_test_info["committer"][0], commit.committer_name
        assert_equal @commits_test_info["committer"][1], commit.committer_email
        assert_equal Time.iso8601(@commits_test_info["committer"][2]), commit.committed_date
        assert_equal @commits_test_info["message"], commit.message
      end
    end

    test "find verifies oid format" do
      assert_raises(RepositoryObjectsCollection::InvalidObjectId) { domain.by_oid(repository: @commits_test_repo, commit_oid: "nope") }
      assert_raises(RepositoryObjectsCollection::InvalidObjectId) { domain.by_oid(repository: @commits_test_repo, commit_oid: "deadbee") }
      assert_raises(RepositoryObjectsCollection::InvalidObjectId) { domain.by_oid(repository: @commits_test_repo, commit_oid: "") }
    end

    test "can check reachability (to see whether the commit is not on a branch or tag)" do
      branch = "temp_test_branch"
      tag    = "temp_test_tag"

      ref      = @commits_test_repo.heads.create(branch, @commits_test_repo.heads.find("master").target_oid, @commits_test_repo.owner)
      metadata = { message: "test commit", committer: @commits_test_repo.owner }
      commit   = ref.append_commit(metadata, @commits_test_repo.owner) {}

      assert_equal commit, domain.by_oid(repository: @commits_test_repo, commit_oid: commit.oid)
      assert_equal commit, domain.by_oid(repository: @commits_test_repo, commit_oid: commit.oid, check_reachability: false)
      assert_equal commit, domain.by_oid(repository: @commits_test_repo, commit_oid: commit.oid, check_reachability: true)

      assert @commits_test_repo.commits.exist?(commit.oid)
      assert @commits_test_repo.commits.exist?(commit.oid, check_reachability: false)
      assert @commits_test_repo.commits.exist?(commit.oid, check_reachability: true)

      assert_equal commit, @commits_test_repo.commits.find_for_sha(commit.oid[0, 20])
      assert_equal commit, @commits_test_repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: false)
      assert_equal commit, @commits_test_repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: true)

      ref.delete(@commits_test_repo.owner)

      assert_equal commit, domain.by_oid(repository: @commits_test_repo, commit_oid: commit.oid)
      assert_equal commit, domain.by_oid(repository: @commits_test_repo, commit_oid: commit.oid, check_reachability: false)
      assert_raises(GitRPC::ObjectMissing) do
        domain.by_oid(repository: @commits_test_repo, commit_oid: commit.oid, check_reachability: true)
      end

      assert @commits_test_repo.commits.exist?(commit.oid)
      assert @commits_test_repo.commits.exist?(commit.oid, check_reachability: false)
      refute @commits_test_repo.commits.exist?(commit.oid, check_reachability: true)

      assert_equal commit, @commits_test_repo.commits.find_for_sha(commit.oid[0, 20])
      assert_equal commit, @commits_test_repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: false)
      assert_nil           @commits_test_repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: true)

      ref = @commits_test_repo.tags.create(tag, commit.oid, @commits_test_repo.owner)

      assert_equal commit, domain.by_oid(repository: @commits_test_repo, commit_oid: commit.oid)
      assert_equal commit, domain.by_oid(repository: @commits_test_repo, commit_oid: commit.oid, check_reachability: false)
      assert_equal commit, domain.by_oid(repository: @commits_test_repo, commit_oid: commit.oid, check_reachability: true)

      assert @commits_test_repo.commits.exist?(commit.oid)
      assert @commits_test_repo.commits.exist?(commit.oid, check_reachability: false)
      assert @commits_test_repo.commits.exist?(commit.oid, check_reachability: true)

      assert_equal commit, @commits_test_repo.commits.find_for_sha(commit.oid[0, 20])
      assert_equal commit, @commits_test_repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: false)
      assert_equal commit, @commits_test_repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: true)

      ref.delete(@commits_test_repo.owner)

      assert_equal commit, domain.by_oid(repository: @commits_test_repo, commit_oid: commit.oid)
      assert_equal commit, domain.by_oid(repository: @commits_test_repo, commit_oid: commit.oid, check_reachability: false)
      assert_raises(GitRPC::ObjectMissing) do
        domain.by_oid(repository: @commits_test_repo, commit_oid: commit.oid, check_reachability: true)
      end

      assert @commits_test_repo.commits.exist?(commit.oid)
      assert @commits_test_repo.commits.exist?(commit.oid, check_reachability: false)
      refute @commits_test_repo.commits.exist?(commit.oid, check_reachability: true)

      assert_equal commit, @commits_test_repo.commits.find_for_sha(commit.oid[0, 20])
      assert_equal commit, @commits_test_repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: false)
      assert_nil           @commits_test_repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: true)

      ref = @commits_test_repo.extended_refs.create("refs/whatever", commit.oid, @commits_test_repo.owner)

      assert_equal commit, domain.by_oid(repository: @commits_test_repo, commit_oid: commit.oid)
      assert_equal commit, domain.by_oid(repository: @commits_test_repo, commit_oid: commit.oid, check_reachability: false)
      assert_raises(GitRPC::ObjectMissing) do
        domain.by_oid(repository: @commits_test_repo, commit_oid: commit.oid, check_reachability: true)
      end

      assert @commits_test_repo.commits.exist?(commit.oid)
      assert @commits_test_repo.commits.exist?(commit.oid, check_reachability: false)
      refute @commits_test_repo.commits.exist?(commit.oid, check_reachability: true)

      assert_equal commit, @commits_test_repo.commits.find_for_sha(commit.oid[0, 20])
      assert_equal commit, @commits_test_repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: false)
      assert_nil           @commits_test_repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: true)

      ref.delete(@commits_test_repo.owner)
    end
  end

  context "find" do
    test "find multiple commits" do
      parent_oid = @commits_test_info["parents"].first
      commits = domain.by_oids(repository: @commits_test_repo, commit_oids: [parent_oid, @commits_test_oid])
      assert_equal 2, commits.size
      assert_equal parent_oid,  T.must(commits[0]).oid
      assert_equal @commits_test_oid, T.must(commits[1]).oid

      assert_empty domain.by_oids(repository: @commits_test_repo, commit_oids: [])
    end

    test "find multiple commits with upcased oids" do
      parent_oid = @commits_test_info["parents"].first
      commits = domain.by_oids(repository: @commits_test_repo, commit_oids: [parent_oid.upcase, @commits_test_oid.upcase])
      assert_equal 2, commits.size
      assert_equal parent_oid,  T.must(commits[0]).oid
      assert_equal @commits_test_oid, T.must(commits[1]).oid
    end

    test "find verifies oid format" do
      assert_raises(RepositoryObjectsCollection::InvalidObjectId) { domain.by_oids(repository: @commits_test_repo, commit_oids: ["nope"]) }
      assert_raises(RepositoryObjectsCollection::InvalidObjectId) { domain.by_oids(repository: @commits_test_repo, commit_oids: ["deadbee"]) }
      assert_raises(RepositoryObjectsCollection::InvalidObjectId) { domain.by_oids(repository: @commits_test_repo, commit_oids: [""]) }
    end

    test "can check reachability for multiple commits at once" do
      branch = "temp_test_branch"
      tag    = "temp_test_tag"

      ref      = @commits_test_repo.heads.create(branch, @commits_test_repo.heads.find("master").target_oid, @commits_test_repo.owner)
      metadata = { message: "test commit", committer: @commits_test_repo.owner }
      commit1  = ref.append_commit(metadata, @commits_test_repo.owner) {}
      commit2  = ref.append_commit(metadata, @commits_test_repo.owner) {}

      commits = [commit1, commit2]
      oids    = commits.collect(&:oid)

      assert_equal commits, domain.by_oids(repository: @commits_test_repo, commit_oids: oids, check_reachability: true)
      assert @commits_test_repo.commits.exist?(oids, check_reachability: true)

      ref.update(commit1.oid, @commits_test_repo.owner)

      assert_raises(GitRPC::ObjectMissing) do
        domain.by_oids(repository: @commits_test_repo, commit_oids: oids, check_reachability: true)
      end
      refute @commits_test_repo.commits.exist?(oids, check_reachability: true)

      ref.delete(@commits_test_repo.owner)
      ref = @commits_test_repo.tags.create(tag, commit2.oid, @commits_test_repo.owner)

      assert_equal commits, domain.by_oids(repository: @commits_test_repo, commit_oids: oids, check_reachability: true)
      assert @commits_test_repo.commits.exist?(oids, check_reachability: true)

      ref.update(commit1.oid, @commits_test_repo.owner)

      assert_raises(GitRPC::ObjectMissing) do
        domain.by_oids(repository: @commits_test_repo, commit_oids: oids, check_reachability: true)
      end
      refute @commits_test_repo.commits.exist?(oids, check_reachability: true)

      ref.delete(@commits_test_repo.owner)
      ref = @commits_test_repo.extended_refs.create("refs/whatever", commit2.oid, @commits_test_repo.owner)

      assert_raises(GitRPC::ObjectMissing) do
        domain.by_oids(repository: @commits_test_repo, commit_oids: oids, check_reachability: true)
      end
      refute @commits_test_repo.commits.exist?(oids, check_reachability: true)

      ref.delete(@commits_test_repo.owner)
    end
  end

  context "rewrite_merge_commit" do
    test "Successfully rewrites merge commit and squashes" do
      Timecop.freeze do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          commit_oid = domain.rewrite_merge_commit(
            repository: @repo,
            commit_oid: @merge_commit.oid,
            info: @web_commit_data,
            squash: true,
            require_signature: false
          )

          assert squashed_commit = @repo.commits.find(commit_oid)

          assert_equal @author_email, squashed_commit.author_email
          assert_equal @author_name, squashed_commit.author_name
          assert_equal @time_zone.name, squashed_commit.authored_date.zone
          assert_equal "#{@title}\n\n#{@message}", squashed_commit.message

          assert_equal GitHub.web_committer_email, squashed_commit.committer_email
          assert_equal GitHub.web_committer_name, squashed_commit.committer_name

          assert_equal 1, squashed_commit.parent_count
          assert_equal @merge_commit.tree_oid, squashed_commit.tree_oid

          assert_hydro_published({
            repository_id: @repo.id,
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            created_at: Time.now,
            commit_shas: [commit_oid],
            start_sha: nil,
            end_sha: nil,
            user_login: nil,
            enabled_flags: Repositories::HydroPushJobFlags::FLAGS.select { |f| GitHub.flipper[f].enabled? }
          }, schema: "github.repositories.v1.CommitsCreated", partition_key: @repo.id)

          assert_hydro_messages(count: 1, schema: "github.repositories.v1.CommitsCreated")
        end
      end
    end

    test "Successfully rewrites merge commit and doesn't squash" do
      Timecop.freeze do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          commit_oid = domain.rewrite_merge_commit(
            repository: @repo,
            commit_oid: @merge_commit.oid,
            info: @web_commit_data,
            squash: false,
            require_signature: false
          )

          assert merged_commit = @repo.commits.find(commit_oid)

          assert_equal @author_email, merged_commit.author_email
          assert_equal @author_name, merged_commit.author_name
          assert_equal @time_zone.name, merged_commit.authored_date.zone
          assert_equal "#{@title}\n\n#{@message}", merged_commit.message

          assert_equal GitHub.web_committer_email, merged_commit.committer_email
          assert_equal GitHub.web_committer_name, merged_commit.committer_name

          assert_equal 2, merged_commit.parent_count
          assert_equal @merge_commit.tree_oid, merged_commit.tree_oid

          assert_hydro_published({
            repository_id: @repo.id,
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            created_at: Time.now,
            commit_shas: [commit_oid],
            start_sha: nil,
            end_sha: nil,
            user_login: nil,
            enabled_flags: Repositories::HydroPushJobFlags::FLAGS.select { |f| GitHub.flipper[f].enabled? }
          }, schema: "github.repositories.v1.CommitsCreated", partition_key: @repo.id)

          assert_hydro_messages(count: 1, schema: "github.repositories.v1.CommitsCreated")
        end
      end
    end

    test "Successfully signs commit", skip_enterprise: true do
      commit_oid = domain.rewrite_merge_commit(
        repository: @repo,
        commit_oid: @merge_commit.oid,
        info: @web_commit_data,
        squash: true,
        require_signature: true
      )

      assert squashed_commit = @repo.commits.find(commit_oid)
      assert squashed_commit.has_signature?
    end

    test "succeeds despite signature failure if signature is not requred" do
      Repository.stubs(:find_by).returns(@repo)
      @repo.stubs(:sign_commit).returns(nil)

      commit_oid = domain.rewrite_merge_commit(
        repository: @repo,
        commit_oid: @merge_commit.oid,
        info: @web_commit_data,
        squash: true,
        require_signature: false
      )

      assert squashed_commit = @repo.commits.find(commit_oid)
      refute squashed_commit.has_signature?
    end

    test "raises Repositories::Error::SignatureError if signature is required but fails" do
      Repository.stubs(:find_by).returns(@repo)
      @repo.stubs(:sign_commit).returns(nil)

      assert_raises Repositories::Error::SignatureError do
        commit_oid = domain.rewrite_merge_commit(
          repository: @repo,
          commit_oid: @merge_commit.oid,
          info: @web_commit_data,
          squash: true,
          require_signature: true
        )
      end
    end
  end

  context "update_committer_info" do
    test "Successfully updates committer info for a range of commits" do
      Timecop.freeze do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          commit_time = Time.parse("2000-01-01T00:00:00Z").iso8601
          commit_oid = domain.update_committer_info(
            repository: @repo2,
            start_commit_oid: @third_commit.oid,
            end_commit_oid: @first_commit.oid,
            email: GitHub.web_committer_email,
            name: GitHub.web_committer_name,
            time: commit_time
          )

          commit = @repo2.commits.find(commit_oid)

          assert_equal @third_commit.author, commit.author
          assert_equal GitHub.web_committer_name, commit.committer_name
          assert_equal GitHub.web_committer_email, commit.committer_email
          assert_equal commit_time, commit.committed_date.iso8601
          assert_equal @third_commit.message, commit.message
          assert_equal @third_commit.tree_oid, commit.tree_oid

          commit = @repo2.commits.find(commit.parent_oids.first)
          assert_equal @second_commit.author, commit.author
          assert_equal GitHub.web_committer_name, commit.committer_name
          assert_equal GitHub.web_committer_email, commit.committer_email
          assert_equal commit_time, commit.committed_date.iso8601
          assert_equal @second_commit.message, commit.message
          assert_equal @second_commit.tree_oid, commit.tree_oid

          commit = @repo2.commits.find(commit.parent_oids.first)
          assert_equal @first_commit, commit

          assert_hydro_published({
            repository_id: @repo2.id,
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            created_at: Time.now,
            commit_shas: nil,
            start_sha: @first_commit.oid,
            end_sha: commit_oid,
            user_login: nil,
            enabled_flags: Repositories::HydroPushJobFlags::FLAGS.select { |f| GitHub.flipper[f].enabled? }
          }, schema: "github.repositories.v1.CommitsCreated", partition_key: @repo2.id)

          assert_hydro_messages(count: 1, schema: "github.repositories.v1.CommitsCreated")
        end
      end
    end
  end

  context "create_tree_changes" do
    test "Successfully creates a new commit with no parent" do
      Timecop.freeze do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          commit_oid = domain.create_tree_changes(
            repository: @repo2,
            parent_oids: nil,
            info: @web_commit_data,
            files: { "README" => "Contents" },
            sign_commit: false,
            signature: nil
          )

          tree_change = @repo2.commits.find(commit_oid)

          assert_equal @author_email, tree_change.author_email
          assert_equal @author_name, tree_change.author_name
          assert_equal @time_zone.name, tree_change.authored_date.zone
          assert_equal "#{@title}\n\n#{@message}", tree_change.message

          assert_equal GitHub.web_committer_email, tree_change.committer_email
          assert_equal GitHub.web_committer_name, tree_change.committer_name

          assert_equal 0, tree_change.parent_count
          refute tree_change.has_signature?

          assert_hydro_published({
            repository_id: @repo2.id,
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            created_at: Time.now,
            commit_shas: [commit_oid],
            start_sha: nil,
            end_sha: nil,
            user_login: nil,
            enabled_flags: Repositories::HydroPushJobFlags::FLAGS.select { |f| GitHub.flipper[f].enabled? }
          }, schema: "github.repositories.v1.CommitsCreated", partition_key: @repo2.id)

          assert_hydro_messages(count: 1, schema: "github.repositories.v1.CommitsCreated")
        end
      end
    end

    test "Successfully creates a new commit with parent commits" do
      Timecop.freeze do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          commit_oid = domain.create_tree_changes(
            repository: @repo2,
            parent_oids: [@third_commit.oid, @second_commit.oid],
            info: @web_commit_data,
            files: { "README" => "Contents" },
            sign_commit: false,
            signature: nil
          )

          tree_change = @repo2.commits.find(commit_oid)

          assert_equal @author_email, tree_change.author_email
          assert_equal @author_name, tree_change.author_name
          assert_equal @time_zone.name, tree_change.authored_date.zone
          assert_equal "#{@title}\n\n#{@message}", tree_change.message

          assert_equal GitHub.web_committer_email, tree_change.committer_email
          assert_equal GitHub.web_committer_name, tree_change.committer_name

          assert_equal 2, tree_change.parent_count
          refute tree_change.has_signature?

          assert_hydro_published({
            repository_id: @repo2.id,
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            created_at: Time.now,
            commit_shas: [commit_oid],
            start_sha: nil,
            end_sha: nil,
            user_login: nil,
            enabled_flags: Repositories::HydroPushJobFlags::FLAGS.select { |f| GitHub.flipper[f].enabled? }
          }, schema: "github.repositories.v1.CommitsCreated", partition_key: @repo2.id)

          assert_hydro_messages(count: 1, schema: "github.repositories.v1.CommitsCreated")
        end
      end
    end

    test "Successfully signs a new commit", skip_enterprise: true do
      commit_oid = domain.create_tree_changes(
        repository: @repo2,
        parent_oids: nil,
        info: @web_commit_data,
        files: { "README" => "Contents" },
        sign_commit: true
      )

      tree_change = @repo2.commits.find(commit_oid)

      assert_equal @author_email, tree_change.author_email
      assert_equal @author_name, tree_change.author_name
      assert_equal @time_zone.name, tree_change.authored_date.zone
      assert_equal "#{@title}\n\n#{@message}", tree_change.message

      assert_equal GitHub.web_committer_email, tree_change.committer_email
      assert_equal GitHub.web_committer_name, tree_change.committer_name

      assert_equal 0, tree_change.parent_count
      assert tree_change.has_signature?
    end

    test "Signing parameter defaults to false when not provided" do
      commit_oid = domain.create_tree_changes(
        repository: @repo2,
        parent_oids: nil,
        info: @web_commit_data,
        files: { "README" => "Contents" }
      )

      tree_change = @repo2.commits.find(commit_oid)

      assert_equal @author_email, tree_change.author_email
      assert_equal @author_name, tree_change.author_name
      assert_equal @time_zone.name, tree_change.authored_date.zone
      assert_equal "#{@title}\n\n#{@message}", tree_change.message

      assert_equal GitHub.web_committer_email, tree_change.committer_email
      assert_equal GitHub.web_committer_name, tree_change.committer_name

      assert_equal 0, tree_change.parent_count
      refute tree_change.has_signature?
    end

    test "Accepts signature for new commit" do
      commit_oid = domain.create_tree_changes(
        repository: @repo2,
        parent_oids: nil,
        info: @web_commit_data,
        files: { "README" => "Contents" },
        signature: "Fake signature"
      )

      tree_change = @repo2.commits.find(commit_oid)

      assert_equal @author_email, tree_change.author_email
      assert_equal @author_name, tree_change.author_name
      assert_equal @time_zone.name, tree_change.authored_date.zone
      assert_equal "#{@title}\n\n#{@message}", tree_change.message

      assert_equal GitHub.web_committer_email, tree_change.committer_email
      assert_equal GitHub.web_committer_name, tree_change.committer_name

      assert_equal 0, tree_change.parent_count
      assert tree_change.has_signature?
      assert_equal tree_change.signature, "Fake signature"
    end

    test "Ignores signature for new commit when sign_commit is true", skip_enterprise: true do
      commit_oid = domain.create_tree_changes(
        repository: @repo2,
        parent_oids: nil,
        info: @web_commit_data,
        files: { "README" => "Contents" },
        sign_commit: true,
        signature: "Fake signature"
      )

      tree_change = @repo2.commits.find(commit_oid)

      assert_equal @author_email, tree_change.author_email
      assert_equal @author_name, tree_change.author_name
      assert_equal @time_zone.name, tree_change.authored_date.zone
      assert_equal "#{@title}\n\n#{@message}", tree_change.message

      assert_equal GitHub.web_committer_email, tree_change.committer_email
      assert_equal GitHub.web_committer_name, tree_change.committer_name

      assert_equal 0, tree_change.parent_count
      assert tree_change.has_signature?
      refute_equal tree_change.signature, "Fake signature"
    end
  end
end
