# typed: true
# frozen_string_literal: true

require "test_helper"

class GistCreatorTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @contents = [{ name: "foo.txt", value: "bar" }]
  end

  test "dangling repo is not left on disk if Gist#save! fails" do
    creator = Gist::Creator.new(contents: @contents, user: @user, public: true)

    boom = ActiveRecord::StatementInvalid.new("boom")
    creator.gist.stubs(:save!).raises(boom)

    assert_raises ActiveRecord::StatementInvalid do
      creator.create
    end

    refute_predicate creator.gist, :persisted?
    refute_predicate creator.gist.rpc, :exist?
  end

  test "dangling record is not left in database if Gist#save! fails during after_commit but after write to db" do
    creator = Gist::Creator.new(contents: @contents, user: @user, public: true)

    boom = ActiveRecord::StatementInvalid.new("boom")
    creator.gist.stubs(:synchronize_search_index).raises(boom)

    assert_raises ActiveRecord::StatementInvalid do
      creator.create
    end

    refute_predicate creator.gist, :persisted?
    refute_predicate creator.gist.rpc, :exist?
  end

  test "failed create leaves gist soft deleted" do

    creator = Gist::Creator.new(contents: @contents, user: @user, public: true)

    boom = Exception.new("boom")
    creator.gist.stubs(:unmemoize_all).raises(boom)

    assert_raises Exception do
      creator.create
    end

    assert_predicate creator.gist, :persisted?
    assert_predicate creator.gist, :delete_flag?
  end

  test "create rejects delete_flag that will be overwritten" do
    error = assert_raises ArgumentError do
      Gist::Creator.new(contents: @contents, user: @user, public: true, delete_flag: true)
    end

    assert_equal "delete_flag is not allowed", error.message
  end

  test "uses the correct repository template" do
    creator = Gist::Creator.new(contents: @contents, user: @user, public: true)
    creator.create
    gist = creator.gist

    hooks_path = File.readlink("#{gist.shard_path}/hooks")
    assert_equal hooks_path, "#{GitHub.gist3_repository_template}/hooks"
  end

  test "creates a new repo with the default branch matching the creating user's setting" do
    creator = Gist::Creator.new(contents: @contents, user: @user, public: true)
    creator.create
    gist = creator.gist

    assert_equal gist.default_branch, @user.default_new_repo_branch

    @user.set_default_new_repo_branch("test", actor: @user)
    assert_equal @user.default_new_repo_branch, "test"
    creator2 = Gist::Creator.new(contents: @contents, user: @user, public: true)
    creator2.create
    assert_equal creator2.gist.default_branch, @user.default_new_repo_branch
  end

  test "increments the pushed count" do
    creator = Gist::Creator.new(contents: @contents, user: @user, public: true)
    perform_enqueued_jobs(only: [GistPushJob]) do
      creator.create
    end
    gist = creator.gist
    gist.reload

    assert_equal 1, gist.pushed_count
    assert_equal 1, gist.pushed_count_since_maintenance
  end

  test "increments the pushed count when forking" do
    forker = create(:user)

    gist = GistHelpers.generate(user: @user,
      contents: @contents,
      description: "some gist description")

    only = [GistPushJob]
    gist_fork = perform_enqueued_jobs(only: only) do
      Gist::Creator.create!(user: forker, parent: gist)
    end
    gist_fork.reload

    assert_equal 1, gist_fork.pushed_count
    assert_equal 1, gist_fork.pushed_count_since_maintenance
  end

  test "cannot create a gist with a path-traversing submodule name" do
    gitmodules_content = <<-GITMODULES
      [submodule "../../something/evil.git"]
        path = totally-innocent
        url = foo
    GITMODULES
    contents = [{ name: ".gitmodules", value: gitmodules_content }]

    assert_raises(GitRPC::BadGitmodules) do
      GistHelpers.generate(user: @user, contents: contents)
    end
  end

  test "cannot create a gist with option-injecting url" do
    gitmodules_content = <<-GITMODULES
      [submodule "evil"]
        path = totally-innocent
        url = -u./payload
    GITMODULES
    contents = [{ name: ".gitmodules", value: gitmodules_content }]

    assert_raises(GitRPC::BadGitmodules) do
      GistHelpers.generate(user: @user, contents: contents)
    end
  end

  test "cannot create a gist with option-injecting path" do
    gitmodules_content = <<-GITMODULES
      [submodule "evil"]
        path = -what
        url = https://example.com/innocent.git
    GITMODULES
    contents = [{ name: ".gitmodules", value: gitmodules_content }]

    assert_raises(GitRPC::BadGitmodules) do
      GistHelpers.generate(user: @user, contents: contents)
    end
  end

  test "cannot create a gist with a gitmodules url injecting into the credential helper" do
    gitmodules_content = <<-GITMODULES
      [submodule "evil"]
        path = totally-innocent
        url = https://example.com/evil?%0ahost=github.com
    GITMODULES
    contents = [{ name: ".gitmodules", value: gitmodules_content }]

    assert_raises(GitRPC::BadGitmodules) do
      GistHelpers.generate(user: @user, contents: contents)
    end
  end

  context "a visibility preference is omitted" do
    test "defaults to private" do
      gist = Gist::Creator.new(contents: @contents, user: @user).create
      assert gist.private?
    end
  end

  context "a fork" do
    test "defaults to visibility of parent (public)" do
      public_parent = GistHelpers.generate(contents: @contents)
      gist = Gist::Creator.new(parent: public_parent, user: @user).create
      refute gist.private?
    end
  end

  context "dgit" do
    test "creates gist replicas" do
      run_dgit_replica_allocation_test \
        expected_count: GitHub.dgit_default_copies
    end

    test "create gist with non-voting replicas" do
      non_voting_hosts = (1..2).map { DGit.add_fileserver(voting: false) }
      GitHub.dgit_non_voting_copies = 2

      run_dgit_replica_allocation_test \
        expected_count: GitHub.dgit_default_copies + 2,
        expected_hosts: non_voting_hosts
    end

    test "create gist without non-voting replicas when they are all offline" do
      non_voting_hosts = (1..2).map { DGit.add_fileserver(voting: false, online: false) }
      GitHub.dgit_non_voting_copies = 2

      run_dgit_replica_allocation_test \
        expected_count: GitHub.dgit_default_copies,
        unexpected_hosts: non_voting_hosts
    end

    test "create gist without non-voting replicas when they are all embargoed" do
      non_voting_hosts = (1..2).map { DGit.add_fileserver(voting: false, embargoed: true) }
      GitHub.dgit_non_voting_copies = 2

      run_dgit_replica_allocation_test \
        expected_count: GitHub.dgit_default_copies,
        unexpected_hosts: non_voting_hosts
    end

    test "create gist with not enough non-voting replicas when there aren't enough" do
      non_voting_host = DGit.add_fileserver(voting: false)
      GitHub.dgit_non_voting_copies = 2

      run_dgit_replica_allocation_test \
        expected_count: GitHub.dgit_default_copies + 1,
        expected_hosts: [non_voting_host]
    end

    test "create gist without non-voting replicas when there aren't any non-voting fileservers" do
      GitHub.dgit_non_voting_copies = 2

      run_dgit_replica_allocation_test \
        expected_count: GitHub.dgit_default_copies
    end
  end

  def run_dgit_replica_allocation_test(expected_count:, expected_hosts: [], unexpected_hosts: [])
    creator = Gist::Creator.new(contents: @contents, user: @user, public: true)
    creator.create
    gist = creator.gist

    gist_replicas = GitHub::DGit::Routing.all_gist_replicas(gist.id)

    assert_equal expected_count, gist_replicas.size, "number of replicas"

    gist_replicas.each do |rep|
      assert_equal true, rep.healthy?, "replica is healthy"
    end

    gist_replica_hosts = gist_replicas.map(&:host)
    expected_hosts.each do |host|
      assert_includes gist_replica_hosts, host, "expected a replica on this host"
    end
    unexpected_hosts.each do |host|
      refute_includes gist_replica_hosts, host, "did not expect a replica on this host"
    end

    gist
  end
end
