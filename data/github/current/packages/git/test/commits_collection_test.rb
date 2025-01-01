# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitsCollectionTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @repo          = create(:repository)
    @grit          = create(:repository)
    @writable_repo = create(:private_repository)

    @owner       = @repo.owner
    @collab      = create(:user)
    @repo.add_member(@collab)
    @collab.watch_repo(@repo)

    @committer   = create(:user, email: "technoweenie@gmail.com", name: "technoweenie")
    @commit_oid  = "3572d83ba062076f6a740379463d0f3f770d7fc5"
    @commit_info = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
    }

    @head_oid    = "391134db5617a614b517ae383cf9f0264fb436e2"
  end

  setup do
    Spokesd.enable_spokesd

    example_repo :commit_test, @repo
    example_repo :mojombo_grit, @grit
    example_repo :simple, @writable_repo
    reset_cache

    @commits = CommitsCollection.new(@repo)

    WebFlowHelper.setup_webflow
  end

  test "commits.find a single commit" do
    [@commit_oid, @commit_oid.upcase].each do |oid|
      commit = @commits.find(oid)
      assert_equal @commit_oid, commit.oid
      assert_equal @commit_info["parents"], commit.parent_oids
      assert_equal @commit_info["tree"], commit.tree_oid
      assert_equal @commit_info["message"], commit.message
      assert_equal @commit_info["author"][0], commit.author_name
      assert_equal @commit_info["author"][1], commit.author_email
      assert_equal Time.iso8601(@commit_info["author"][2]), commit.authored_date
      assert_equal @commit_info["committer"][0], commit.committer_name
      assert_equal @commit_info["committer"][1], commit.committer_email
      assert_equal Time.iso8601(@commit_info["committer"][2]), commit.committed_date
      assert_equal @commit_info["message"], commit.message
    end

    assert_nil @commits.find(nil)
  end

  test "commits.find multiple commits" do
    parent_oid = @commit_info["parents"].first
    commits = @commits.find([parent_oid, @commit_oid])
    assert_equal 2, commits.size
    assert_equal parent_oid,  commits[0].oid
    assert_equal @commit_oid, commits[1].oid
  end

  test "commits.find multiple commits with upcased oids" do
    parent_oid = @commit_info["parents"].first
    commits = @commits.find([parent_oid.upcase, @commit_oid.upcase])
    assert_equal 2, commits.size
    assert_equal parent_oid,  commits[0].oid
    assert_equal @commit_oid, commits[1].oid
  end

  test "commits.find verifies oid format" do
    assert_raises(RepositoryObjectsCollection::InvalidObjectId) { @commits.find("nope") }
    assert_raises(RepositoryObjectsCollection::InvalidObjectId) { @commits.find("deadbee") }
    assert_raises(RepositoryObjectsCollection::InvalidObjectId) { @commits.find("") }
  end

  test "commits.exist? with a single commit" do
    assert @commits.exist?(@commit_oid)
    assert !@commits.exist?("deadbeedeadbeedeadbeedeadbeedeadbeedeadb")
    assert_raises(RepositoryObjectsCollection::InvalidObjectId) { @commits.exist?("deadbee") }
  end

  test "commits.exist? with multiple commits" do
    parent_oid = @commit_info["parents"].first
    assert @commits.exist?([parent_oid, @commit_oid])
    assert !@commits.exist?([@commit_oid, "deadbeedeadbeedeadbeedeadbeedeadbeedeadb"])
    assert_raises(RepositoryObjectsCollection::InvalidObjectId) { @commits.exist?([@commit_oid, "deadbee"]) }
  end

  test "commits.search for exact author" do
    results = @commits.search("author", "technoweenie@gmail.com", @commit_oid)
    assert_match "technoweenie@gmail.com", results[0].author_email
    assert_equal 2, results.size
  end

  test "commits.search for exact committer" do
    results = @commits.search("committer", "technoweenie@gmail.com", @commit_oid)
    assert_match "technoweenie@gmail.com", results[0].committer_email
    assert_equal 2, results.size
  end

  test "commits.search for fuzzy author" do
    results = @commits.search("author", "techno", @commit_oid)
    assert_match "technoweenie@gmail.com", results[0].author_email
    assert_equal 2, results.size
  end

  test "commits.search for fuzzy committer" do
    results = @commits.search("committer", "techno", @commit_oid)
    assert_match "technoweenie@gmail.com", results[0].committer_email
    assert_equal 2, results.size
  end

  test "commits.search for commit messages" do
    results = @commits.search("grep", "space change", @commit_oid)
    assert_match @commit_oid, results[0].oid
    assert_equal 1, results.size
  end

  test "commits.find_for_sha with short sha" do
    result = @commits.find_for_sha(@commit_oid[0, 10])
    assert_match @commit_oid, result.oid
  end

  test "commits.find_for_sha with oid" do
    result = @commits.find_for_sha(@commit_oid)
    assert_match @commit_oid, result.oid
  end

  test "commits.find_for_sha with nonexistent oid" do
    result = @commits.find_for_sha(@commit_info["tree"])
    assert_nil result
  end

  test "commits.find_for_sha with nonexistent short sha" do
    result = @commits.find_for_sha(@commit_info["tree"][0, 10])
    assert_nil result
  end

  test "commits.find_for_sha with ref" do
    result = @commits.find_for_sha("abcdef1234")
    assert_nil result

    @repo.heads.create("abcdef1234", @commit_oid, @owner)
    result = @commits.find_for_sha("abcdef1234")
    assert_nil result

    assert_raises RepositoryObjectsCollection::InvalidObjectId do
      @commits.find_for_sha("master")
    end
  end

  test "can check reachability (to see whether the commit is not on a branch or tag)" do
    branch = "temp_test_branch"
    tag    = "temp_test_tag"

    ref      = @repo.heads.create(branch, @repo.heads.find("master").target_oid, @repo.owner)
    metadata = { message: "test commit", committer: @repo.owner }
    commit   = ref.append_commit(metadata, @repo.owner) {}

    assert_equal commit, @repo.commits.find(commit.oid)
    assert_equal commit, @repo.commits.find(commit.oid, check_reachability: false)
    assert_equal commit, @repo.commits.find(commit.oid, check_reachability: true)

    assert @repo.commits.exist?(commit.oid)
    assert @repo.commits.exist?(commit.oid, check_reachability: false)
    assert @repo.commits.exist?(commit.oid, check_reachability: true)

    assert_equal commit, @repo.commits.find_for_sha(commit.oid[0, 20])
    assert_equal commit, @repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: false)
    assert_equal commit, @repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: true)

    ref.delete(@repo.owner)

    assert_equal commit, @repo.commits.find(commit.oid)
    assert_equal commit, @repo.commits.find(commit.oid, check_reachability: false)
    assert_raises(GitRPC::ObjectMissing) do
      @repo.commits.find(commit.oid, check_reachability: true)
    end

    assert @repo.commits.exist?(commit.oid)
    assert @repo.commits.exist?(commit.oid, check_reachability: false)
    refute @repo.commits.exist?(commit.oid, check_reachability: true)

    assert_equal commit, @repo.commits.find_for_sha(commit.oid[0, 20])
    assert_equal commit, @repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: false)
    assert_nil           @repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: true)

    ref = @repo.tags.create(tag, commit.oid, @repo.owner)

    assert_equal commit, @repo.commits.find(commit.oid)
    assert_equal commit, @repo.commits.find(commit.oid, check_reachability: false)
    assert_equal commit, @repo.commits.find(commit.oid, check_reachability: true)

    assert @repo.commits.exist?(commit.oid)
    assert @repo.commits.exist?(commit.oid, check_reachability: false)
    assert @repo.commits.exist?(commit.oid, check_reachability: true)

    assert_equal commit, @repo.commits.find_for_sha(commit.oid[0, 20])
    assert_equal commit, @repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: false)
    assert_equal commit, @repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: true)

    ref.delete(@repo.owner)

    assert_equal commit, @repo.commits.find(commit.oid)
    assert_equal commit, @repo.commits.find(commit.oid, check_reachability: false)
    assert_raises(GitRPC::ObjectMissing) do
      @repo.commits.find(commit.oid, check_reachability: true)
    end

    assert @repo.commits.exist?(commit.oid)
    assert @repo.commits.exist?(commit.oid, check_reachability: false)
    refute @repo.commits.exist?(commit.oid, check_reachability: true)

    assert_equal commit, @repo.commits.find_for_sha(commit.oid[0, 20])
    assert_equal commit, @repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: false)
    assert_nil           @repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: true)

    ref = @repo.extended_refs.create("refs/whatever", commit.oid, @repo.owner)

    assert_equal commit, @repo.commits.find(commit.oid)
    assert_equal commit, @repo.commits.find(commit.oid, check_reachability: false)
    assert_raises(GitRPC::ObjectMissing) do
      @repo.commits.find(commit.oid, check_reachability: true)
    end

    assert @repo.commits.exist?(commit.oid)
    assert @repo.commits.exist?(commit.oid, check_reachability: false)
    refute @repo.commits.exist?(commit.oid, check_reachability: true)

    assert_equal commit, @repo.commits.find_for_sha(commit.oid[0, 20])
    assert_equal commit, @repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: false)
    assert_nil           @repo.commits.find_for_sha(commit.oid[0, 20], check_reachability: true)

    ref.delete(@repo.owner)
  end

  test "can check reachability for multiple commits at once" do
    branch = "temp_test_branch"
    tag    = "temp_test_tag"

    ref      = @repo.heads.create(branch, @repo.heads.find("master").target_oid, @repo.owner)
    metadata = { message: "test commit", committer: @repo.owner }
    commit1  = ref.append_commit(metadata, @repo.owner) {}
    commit2  = ref.append_commit(metadata, @repo.owner) {}

    commits = [commit1, commit2]
    oids    = commits.collect(&:oid)

    assert_equal commits, @repo.commits.find(oids, check_reachability: true)
    assert @repo.commits.exist?(oids, check_reachability: true)

    ref.update(commit1.oid, @repo.owner)

    assert_raises(GitRPC::ObjectMissing) do
      @repo.commits.find(oids, check_reachability: true)
    end
    refute @repo.commits.exist?(oids, check_reachability: true)

    ref.delete(@repo.owner)
    ref = @repo.tags.create(tag, commit2.oid, @repo.owner)

    assert_equal commits, @repo.commits.find(oids, check_reachability: true)
    assert @repo.commits.exist?(oids, check_reachability: true)

    ref.update(commit1.oid, @repo.owner)

    assert_raises(GitRPC::ObjectMissing) do
      @repo.commits.find(oids, check_reachability: true)
    end
    refute @repo.commits.exist?(oids, check_reachability: true)

    ref.delete(@repo.owner)
    ref = @repo.extended_refs.create("refs/whatever", commit2.oid, @repo.owner)

    assert_raises(GitRPC::ObjectMissing) do
      @repo.commits.find(oids, check_reachability: true)
    end
    refute @repo.commits.exist?(oids, check_reachability: true)

    ref.delete(@repo.owner)
  end

  test "commits.history" do
    commits = @commits.history(@head_oid)
    assert_equal 4, commits.size
    assert commits.first.instance_of?(::Commit)

    assert_equal @repo.revision_list(@head_oid), commits.map(&:oid)
  end

  test "commits.history with limiting" do
    commits = @commits.history(@head_oid, 2)
    assert_equal 2, commits.size
    assert_equal @repo.revision_list(@head_oid, 2), commits.map(&:oid)
  end

  test "commits.history with skipping" do
    commits = @commits.history(@head_oid, nil, 1)
    assert_equal 3, commits.size
    assert_equal @repo.revision_list(@head_oid, 30, 1), commits.map(&:oid)
  end

  test "commits.history for a path" do
    commits = @commits.history(@head_oid, nil, 0, "geometry.js")
    assert_equal 3, commits.size
    assert commits.first.instance_of?(::Commit)

    assert_equal @repo.revision_list(@head_oid, nil, 0, "geometry.js"),
      commits.map(&:oid)
  end

  test "revision_list strips off leading slashes" do
    commits = @commits.history(@head_oid, nil, 0, "geometry.js")
    assert_equal 3, commits.count

    assert_equal @repo.revision_list(@head_oid, nil, 0, "///geometry.js"), commits.map(&:oid)
  end

  test "commits.paged_history" do
    commits = @commits.paged_history(@head_oid, page = 1, per = 2)
    assert commits.first.instance_of?(::Commit)
    assert_equal 2, commits.count
    assert_equal @repo.revision_list(@head_oid, max = 2), commits.map(&:oid)

    commits = @commits.paged_history(@head_oid, page = 2, per = 2)
    assert commits.first.instance_of?(::Commit)
    assert_equal 2, commits.count
    assert_equal @repo.revision_list(@head_oid, max = 2, skip = 2), commits.map(&:oid)
  end

  test "commits.paged_history with bad pages" do
    assert_equal 0, @commits.paged_history(@head_oid, page = 10, per = 2).count
  end

  test "commits.paged_history for a path" do
    commits = @commits.paged_history(@head_oid, page = 1, per = 2, "geometry.js")
    assert_equal 2, commits.size
    assert commits.first.instance_of?(::Commit)
    assert_equal @repo.revision_list(@head_oid, max = 2, skip = 0, "geometry.js"),
      commits.map(&:oid)

    commits = @commits.paged_history(@head_oid, page = 2, per = 2, "geometry.js")
    assert_equal 1, commits.size
    assert commits.first.instance_of?(::Commit)
    assert_equal @repo.revision_list(@head_oid, max = 2, skip = 2, "geometry.js"),
      commits.map(&:oid)
  end

  test "commits.last_touched for a path on master" do
    base_oid = @grit.ref_to_sha("master")
    base = @grit.commits.last_touched("master")
    assert base.is_a?(Commit)
    assert_equal base_oid, base.oid

    bin_oid = "634396b2f541a9f2d58b00be1a07f0c358b999b3" # recent for bin/ + master
    bin = @grit.commits.last_touched("master", "bin")

    assert bin.is_a?(Commit)
    assert_equal bin_oid, bin.oid
  end

  test "commits.last_touched for a path on a branch" do
    base_oid = "86264f45ff4bcd3da195f5c83f7e414ed4a71628" # recent for lazy_delegator root
    base     = @grit.commits.last_touched("lazy_delegator")

    assert base.is_a?(Commit)
    assert_equal base_oid, base.oid

    libgrit_oid = "4c596908ce1136e8c32174ba13892c6fe68a010d" # recent for lib/grit + lazy_delegator
    libgrit = @grit.commits.last_touched("lazy_delegator", "lib/grit")

    assert libgrit.is_a?(Commit)
    assert_equal libgrit_oid, libgrit.oid
  end

  test "commits.last_touched for a bogus OID" do
    assert_nil @grit.commits.last_touched("deadbeef" * 5)
  end

  test "commits.except loads commits for oids excluding other oids" do
    head_oid    = "1d22e6fde59c9ded9b8093cf26213a5bd9d4c5ec"
    exclude_oid = "337539e896b8c85cc043a923c8fbb927f58e6450"
    commits = @grit.commits.except([head_oid], [exclude_oid])
    assert_equal 5, commits.size
    assert commits.first.instance_of?(Commit)

    assert_equal @grit.revision_list(head_oid)[0, 5], commits.map(&:oid)
  end

  test "commits.create a basic commit" do
    offset   = T.let(nil, T.nilable(Integer))
    commit   = T.let(nil, T.nilable(Commit))
    message  = "test commit"
    metadata = { message: message, committer: @committer }

    Time.use_zone "Europe/Moscow" do
      offset = Time.zone.now.utc_offset
      oid    = @writable_repo.heads.find("master").target_oid

      Timecop.freeze do
        with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
          commit = @writable_repo.commits.create(metadata, oid) do |files|
            files.add("my_new_file.txt", "check this out!\n")
          end

          assert_hydro_published({
            repository_id: @writable_repo.id,
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            created_at: Time.now,
            commit_shas: [commit.oid],
            start_sha: nil,
            end_sha: nil,
            user_login: nil,
            enabled_flags: Repositories::HydroPushJobFlags::FLAGS.select { |f| GitHub.flipper[f].enabled? }
          }, schema: "github.repositories.v1.CommitsCreated", partition_key: @writable_repo.id)

          assert_hydro_messages(count: 1, schema: "github.repositories.v1.CommitsCreated")
        end
      end
    end

    raw_time = commit.instance_variable_get("@authored_date_value")
    assert_equal message, commit&.message
    assert_equal @committer.git_author_name, commit&.committer_name
    assert_equal offset, raw_time[1]
  end

  test "commits.create a commit with files having different permissions" do
    oid = @writable_repo.heads.find("master").target_oid
    message = "test commit"
    metadata = { message: message, committer: @committer }

    commit = @writable_repo.commits.create(metadata, oid) do |files|
      files.add("script.sh", "#!/bin/bash\necho \"hello world\"", mode: 0100755)
      files.add("readme.txt", "Hello World")
    end

    assert_equal message, commit.message
    assert_equal @committer.git_author_name, commit.committer_name
    exe_tree_entry = @writable_repo.blob(commit.oid, "script.sh")
    assert_equal "100755", exe_tree_entry.mode
    non_exe_tree_entry = @writable_repo.blob(commit.oid, "readme.txt")
    assert_equal "100644", non_exe_tree_entry.mode
  end

  test "commits.create a commit with a custom committed date" do
    committed_date = Date.yesterday.to_time

    new_commit_oid = @writable_repo.commits.create(
      {
        message: "test commit",
        committer: @committer,
        committed_date: committed_date.iso8601,
      },
      @writable_repo.ref_to_sha("master"),
    ) do |files|
      files.add("my_new_file.txt", "check this out!\n")
    end.oid

    commit = @writable_repo.commits.find(new_commit_oid)

    assert_equal committed_date, commit.committed_date
  end

  test "commits.create when the author and committer are different" do
    author = create(:user)

    new_commit_oid = @writable_repo.commits.create(
      { message: "test commit", committer: @committer, author: author },
      @writable_repo.ref_to_sha("master"),
    ) do |files|
      files.add("my_new_file.txt", "check this out!\n")
    end.oid

    commit = @writable_repo.commits.find(new_commit_oid)

    assert_equal author.git_author_name, commit.author_name
    assert_equal author.git_author_email, commit.author_email
    refute_equal commit.committer_name, commit.author_name
    refute_equal commit.committer_email, commit.author_email
  end

  test "commits.create with a hash for committer" do
    committer_hash = { name: "Hash This", email: "hash@this.com" }

    new_commit_oid = @writable_repo.commits.create(
      { message: "test commit", committer: committer_hash },
      @writable_repo.ref_to_sha("master"),
    ) do |files|
      files.add("my_new_file.txt", "check this out!\n")
    end.oid

    commit = @writable_repo.commits.find(new_commit_oid)

    assert_equal committer_hash[:name], commit.committer_name
    assert_equal committer_hash[:email], commit.committer_email
  end

  test "commits.create with a User for committer and a hash for author" do
    author_hash = { name: "Hash This", email: "hash@this.com" }

    new_commit_oid = @writable_repo.commits.create(
      {
        message: "test commit",
        committer: @committer,
        author: author_hash,
      },
      @writable_repo.ref_to_sha("master"),
    ) do |files|
      files.add("my_new_file.txt", "check this out!\n")
    end.oid

    commit = @writable_repo.commits.find(new_commit_oid)

    assert_equal author_hash[:name], commit.author_name
    assert_equal author_hash[:email], commit.author_email
    refute_equal commit.committer_name, commit.author_name
    refute_equal commit.committer_email, commit.author_email
  end

  test "commits.create with no committer" do
    new_commit_oid = @writable_repo.commits.create(
      {
        message: "test commit",
        author: @committer,
      },
      @writable_repo.ref_to_sha("master"),
    ) do |files|
      files.add("my_new_file.txt", "check this out!\n")
    end.oid

    commit = @writable_repo.commits.find(new_commit_oid)

    assert_equal @committer.git_author_name,  commit.author_name
    assert_equal @committer.git_author_email, commit.author_email
    assert_equal GitHub.web_committer_name,  commit.committer_name
    assert_equal GitHub.web_committer_email, commit.committer_email
  end

  context "commits.create when author is a Mannequin" do
    test "with nil email uses stealth email for commit author email" do
      mannequin = create(:mannequin, email: nil)

      new_commit_oid = @writable_repo.commits.create(
        {
          message: "test commit",
          committer: @committer,
          author: mannequin,
        },
        @writable_repo.ref_to_sha("master"),
      ) do |files|
        files.add("my_new_file.txt", "check this out!\n")
      end.oid

      commit = @writable_repo.commits.find(new_commit_oid)

      assert_equal mannequin.login, commit.author_name
      assert_equal mannequin.anonymous_user_email, commit.author_email
      refute_equal commit.committer_name, commit.author_name
      refute_equal commit.committer_email, commit.author_email
    end

    test "with valid email uses mannequin email for commit author email" do
      mannequin = create(:mannequin)
      new_commit_oid = @writable_repo.commits.create(
        {
          message: "test commit",
          committer: @committer,
          author: mannequin,
        },
        @writable_repo.ref_to_sha("master"),
      ) do |files|
        files.add("my_new_file.txt", "check this out!\n")
      end.oid

      commit = @writable_repo.commits.find(new_commit_oid)

      assert_equal mannequin.login, commit.author_name
      assert_equal mannequin.email, commit.author_email
      refute_equal commit.committer_name, commit.author_name
      refute_equal commit.committer_email, commit.author_email
    end
  end

  test "commits.create with no committer or author" do
    assert_raises(ArgumentError) do
      new_commit_oid = @writable_repo.commits.create(
        {
          message: "test commit",
        },
        @writable_repo.ref_to_sha("master"),
      ) do |files|
        files.add("my_new_file.txt", "check this out!\n")
      end.oid
    end
  end

  test "commits.create with a removal" do
    new_commit_oid = @writable_repo.commits.create(
      { message: "test commit", committer: @committer },
      @writable_repo.ref_to_sha("master"),
    ) do |files|
      files.remove("a")
    end.oid

    commit = @writable_repo.commits.find(new_commit_oid)
    entries = @writable_repo.read_objects([commit.tree_oid], :tree, feature_flag: :commits_collection_test).first["entries"]

    # Make sure there's only one file left and it's not the one that was removed
    assert_equal 1, entries.count
    refute_equal "a", entries.keys[0]
  end

  test "commits.create with a move" do
    new_data = "changed"

    new_commit_oid = @writable_repo.commits.create(
      { message: "test commit", committer: @committer },
      @writable_repo.ref_to_sha("master"),
    ) do |files|
      files.move("a", "b", new_data)
    end.oid

    commit    = @writable_repo.commits.find(new_commit_oid)
    tree      = @writable_repo.read_objects([commit.tree_oid], :tree, feature_flag: :commits_collection_test).first
    entries   = tree["entries"]
    filenames = entries.keys

    # Make sure the old file is gone and the new one is there.
    assert_includes filenames, "b"
    refute_includes filenames, "a"

    # Make sure the new file has the new data.
    new_blob = @writable_repo.rpc.read_blobs([entries["b"]["oid"]]).first
    assert_equal new_data, new_blob["data"]
  end

  test "commits.create with an add, remove, and move" do
    new_commit_oid = @writable_repo.commits.create(
      { message: "test commit", committer: @committer },
      @writable_repo.ref_to_sha("master"),
    ) do |files|
      files.add("new_stuff.txt", "how u doin")
      files.remove("a")
      files.move("empty_file", "full_file", "new data")
    end.oid

    commit    = @writable_repo.commits.find(new_commit_oid)
    tree      = @writable_repo.read_objects([commit.tree_oid], :tree, feature_flag: :commits_collection_test).first
    entries   = tree["entries"]
    filenames = entries.keys

    # Make sure all the files are as we expect
    assert_equal 2, entries.count
    assert_includes filenames, "new_stuff.txt"
    assert_includes filenames, "full_file"
    refute_includes filenames, "a"
  end

  test "commits.create caches default author email when custom author email is used" do
    cache_key = @committer.default_author_email_cache_key(@writable_repo)
    assert_nil Users::Kv.store.get(cache_key).value { "error" }

    commit   = T.let(nil, T.nilable(Commit))
    message  = "test commit"

    # You need at least 2 verified email addresses to have an author_email.
    @committer.emails.first.verify!
    email2 = @committer.add_email("yo@github.com")
    email2.verify!
    custom_author_email = @committer.author_emails.first
    metadata = { message: message, committer: @committer, author_email: custom_author_email }

    Time.use_zone "Europe/Moscow" do
      oid    = @writable_repo.heads.find("master").target_oid

      commit = @writable_repo.commits.create(metadata, oid) do |files|
        files.add("my_new_file.txt", "check this out!\n")
      end
    end

    if GitHub.enterprise?
      # Disabled by GitHub.choose_commit_email_enabled? on enterprise.
      assert_nil custom_author_email
    else
      assert_equal custom_author_email, Users::Kv.store.get(cache_key).value { "error" }
    end
  end

  test "commits.create builds files from tree if included" do
    head_oid = @writable_repo.heads.find("master").target_oid
    new_branch = @writable_repo.heads.create("new-branch", head_oid, @writable_repo.owner)
    new_branch_oid = new_branch.target_oid

    new_branch_commit_metadata = {
      message: "Remove existing files and add a new file that only exists on `new-branch`",
      committer: @committer
    }
    commit_on_new_branch = @writable_repo.commits.create(new_branch_commit_metadata, new_branch_oid) do |files|
      files.remove("a")
      files.remove("empty_file")
      files.add("new-file", "not on default branch")
    end

    existing_tree_oid, existing_entries, _truncated = \
      @writable_repo.tree_entries(commit_on_new_branch.oid, "")
    assert_equal existing_entries.map(&:name), ["new-file"]

    default_branch_commit_metadata = {
      message: "Creating new commit on default branch with files from an existing tree",
      committer: @committer,
      tree: existing_tree_oid
    }
    commit_on_default_branch = @writable_repo.commits.create(default_branch_commit_metadata, head_oid)

    new_tree_oid, entries, _truncated = @writable_repo.tree_entries(commit_on_default_branch.oid, "")
    assert_equal new_tree_oid, existing_tree_oid
    assert_equal entries.map(&:name), ["new-file"]
  end

  test "commits.create raises error if attempting to build from tree and files block" do
    exception = assert_raises ArgumentError do
      @writable_repo.commits.create(
        { message: "test commit", committer: @committer, tree: "74ad0f997b34fa77abb99c4ba77088fafd4a9c2c" }
      ) do |files|
        files.add("not-allowed.txt", "boom")
      end
    end
    assert_match /Block not allowed when tree is passed/, exception.message
  end

  test "commits.create with no files block and no tree" do
    exception = assert_raises ArgumentError do
      @writable_repo.commits.create(
        { message: "test commit", committer: @committer },
      )
    end
    assert_match /Files block or tree must be passed/, exception.message
  end

  test "commits.create on an invalid commit" do
    assert_raises GitRPC::Failure do
      # Creating a commit with no message
      @writable_repo.commits.create({ committer: @committer }) do |files|
        files.add("my_new_file.txt", "check this out!\n")
      end
    end
  end

  test "commits.create when adding a nil content file" do
    assert_raises ArgumentError do
      @writable_repo.commits.create(
        { message: "test commit", committer: @committer },
      ) do |files|
        files.add("my_new_file.txt", nil)
      end
    end
  end

  test "commits.create when moving a file and giving nil content" do
    assert_raises ArgumentError do
      @writable_repo.commits.create(
        { message: "test commit", committer: @committer },
      ) do |files|
        files.move("empty_file", "full_file", nil)
      end
    end
  end

  test "commits.create_revert_commit" do
    oid = @writable_repo.commits.create({ message: "commit one", author: @committer }, @writable_repo.ref_to_sha("master")) do |files|
      files.add("f", "content one\n")
    end.oid
    assert_equal(@writable_repo.blob(oid, "f").data, "content one\n")

    oid = @writable_repo.commits.create({ message: "commit two", author: @committer }, oid) do |files|
      files.add("f", "content two\n")
    end.oid
    assert_equal(@writable_repo.blob(oid, "f").data, "content two\n")

    Timecop.freeze do
      with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
        oid = @writable_repo.commits.create_revert_commit(@committer, oid, oid).first.oid
        assert_equal(@writable_repo.blob(oid, "f").data, "content one\n")

        assert_hydro_published({
          repository_id: @writable_repo.id,
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          created_at: Time.now,
          commit_shas: [oid],
          start_sha: nil,
          end_sha: nil,
          user_login: nil,
          enabled_flags: Repositories::HydroPushJobFlags::FLAGS.select { |f| GitHub.flipper[f].enabled? }
        }, schema: "github.repositories.v1.CommitsCreated", partition_key: @writable_repo.id)

        assert_hydro_messages(count: 3, schema: "github.repositories.v1.CommitsCreated")
      end
    end
  end

  context "#async_last_touched" do
    test "nil commitish uses master ref" do
      assert_equal "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
        @writable_repo.async_last_touched(nil, nil).sync.oid
    end

    test "commitish scopes to ref" do
      assert_equal "e91a032dc9f19058a375fb3db68c9dda73527d13",
        @writable_repo.async_last_touched("cr-line-endings", nil).sync.oid
    end

    test "scopes to expected path" do
      assert_equal "2c6363c328126bdee83e9f8dd55ad1db3a2aa160",
        @writable_repo.async_last_touched(nil, "empty_file").sync.oid
    end
  end

  context "commit signing" do
    test "commits.create_revert_commit commit is signed" do
      oid = @writable_repo.commits.create({ message: "commit one", author: @committer }, @writable_repo.ref_to_sha("master")) do |files|
        files.add("f", "content one\n")
      end.oid
      assert_equal(@writable_repo.blob(oid, "f").data, "content one\n")

      oid = @writable_repo.commits.create({ message: "commit two", author: @committer }, oid) do |files|
        files.add("f", "content two\n")
      end.oid
      assert_equal(@writable_repo.blob(oid, "f").data, "content two\n")

      oid = @writable_repo.commits.create_revert_commit(@committer, oid, oid).first.oid
      assert_equal(@writable_repo.blob(oid, "f").data, "content one\n")

      commit = @writable_repo.commits.find(oid)
      assert_predicate commit, :verified_signature?
    end

    test "commits.create_revert_commit commit signing error handling" do
      GitHub.gpg.stubs(:sign).raises(GpgVerify::EarthsmokeError)

      oid = @writable_repo.commits.create({ message: "commit one", author: @committer }, @writable_repo.ref_to_sha("master")) do |files|
        files.add("f", "content one\n")
      end.oid
      assert_equal(@writable_repo.blob(oid, "f").data, "content one\n")

      oid = @writable_repo.commits.create({ message: "commit two", author: @committer }, oid) do |files|
        files.add("f", "content two\n")
      end.oid
      assert_equal(@writable_repo.blob(oid, "f").data, "content two\n")

      oid = @writable_repo.commits.create_revert_commit(@committer, oid, oid).first.oid
      assert_equal(@writable_repo.blob(oid, "f").data, "content one\n")

      commit = @writable_repo.commits.find(oid)
      refute_predicate commit, :has_signature?
    end

    test "signs commits with no committer (web committer)" do
      new_commit_oid = @writable_repo.commits.create(
        {
          message: "test commit",
          author: @committer,
        },
        @writable_repo.ref_to_sha("master"),
        sign: true,
      ) do |files|
        files.add("my_new_file.txt", "check this out!\n")
      end.oid

      commit = @writable_repo.commits.find(new_commit_oid)
      assert_predicate commit, :verified_signature?
    end

    test "doesn't sign commits with no committer if missing sign: arg (web committer)" do
      new_commit_oid = @writable_repo.commits.create(
        {
          message: "test commit",
          author: @committer,
        },
        @writable_repo.ref_to_sha("master"),
      ) do |files|
        files.add("my_new_file.txt", "check this out!\n")
      end.oid

      commit = @writable_repo.commits.find(new_commit_oid)
      refute_predicate commit, :has_signature?
    end

    test "doesn't sign commits with committer" do
      new_commit_oid = @writable_repo.commits.create(
        {
          message: "test commit",
          author: @committer,
          committer: @committer,
        },
        @writable_repo.ref_to_sha("master"),
        sign: true,
      ) do |files|
        files.add("my_new_file.txt", "check this out!\n")
      end.oid

      commit = @writable_repo.commits.find(new_commit_oid)
      refute_predicate commit, :has_signature?
    end

    test "commit signing error handling" do
      GitHub.gpg.stubs(:sign).raises(GpgVerify::EarthsmokeError)

      new_commit_oid = @writable_repo.commits.create(
        {
          message: "test commit",
          author: @committer,
        },
        @writable_repo.ref_to_sha("master"),
        sign: true,
      ) do |files|
        files.add("my_new_file.txt", "check this out!\n")
      end.oid

      commit = @writable_repo.commits.find(new_commit_oid)
      refute_predicate commit, :has_signature?
    end
  end if GitHub.web_commit_signing_enabled?
end
