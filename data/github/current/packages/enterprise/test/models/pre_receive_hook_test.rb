# typed: true
# frozen_string_literal: true

require "test_helper"

class PreReceiveHookTest < GitHub::TestCase
  fixtures do
    @hook = create :pre_receive_hook
    @org = create(:organization)
    @repo = create :repository, owner: @org, name: "org-repo"
    @env = create(:pre_receive_environment)
  end

  test "requires an environment" do
    hook = PreReceiveHook.new name: "a name", repository: create(:repository, :minimal), script: "script.rb"
    assert !hook.valid?
    hook.environment = create(:pre_receive_environment)
    assert hook.valid?
  end

  test "requires a name" do
    hook = PreReceiveHook.new environment: create(:pre_receive_environment), repository: create(:repository, :minimal), script: "script.rb"
    assert !hook.valid?
    hook.name = "a name"
    assert hook.valid?
  end

  test "requires a repository" do
    hook = PreReceiveHook.new name: "a name", environment: create(:pre_receive_environment), script: "script.rb"
    assert !hook.valid?
    hook.repository = create(:repository, :minimal)
    assert hook.valid?
  end

  test "requires a script" do
    hook = PreReceiveHook.new name: "a name", repository: create(:repository, :minimal), environment: create(:pre_receive_environment)
    assert !hook.valid?
    hook.script = "script.rb"
    assert hook.valid?
  end

  test "responds to targets" do
    skip "https://github.com/github/github/issues/358971"

    hook = PreReceiveHook.create name: "a name", repository: create(:repository), environment: create(:pre_receive_environment), script: "script.rb"
    target = create :pre_receive_hook_target, hook: hook
    assert_equal target, hook.targets.first
  end

  test "destroying a hook destroys all targets" do
    skip "https://github.com/github/github/issues/358971"

    hook = PreReceiveHook.create name: "a name", repository: create(:repository), environment: create(:pre_receive_environment), script: "script.rb"
    target1 = create :pre_receive_hook_target, hook: hook
    target2 = create :pre_receive_hook_target, hook: hook
    target3 = create :pre_receive_hook_target, hook: hook

    assert PreReceiveHook.find_by(id: hook.id)
    assert PreReceiveHookTarget.find_by(id: target1.id)
    assert PreReceiveHookTarget.find_by(id: target2.id)
    assert PreReceiveHookTarget.find_by(id: target3.id)

    hook.destroy

    assert !PreReceiveHook.find_by(id: hook.id)
    assert !PreReceiveHookTarget.find_by(id: target1.id)
    assert !PreReceiveHookTarget.find_by(id: target2.id)
    assert !PreReceiveHookTarget.find_by(id: target3.id)
  end

  test "name must be unique" do
    skip "https://github.com/github/github/issues/358971"

    PreReceiveHook.create name: "a name", repository: create(:repository), environment: create(:pre_receive_environment), script: "script.rb"

    hook = PreReceiveHook.new name: "a name", repository: create(:repository, :minimal), environment: create(:pre_receive_environment), script: "script1.rb"
    assert !hook.valid?
    hook.name = "another name"
    assert hook.valid?

    hook = PreReceiveHook.new name: "A NAME", repository: create(:repository, :minimal), environment: create(:pre_receive_environment), script: "script1.rb"
    refute hook.valid?
  end

  test "valid for GB18030 name" do
    hook = PreReceiveHook.new environment: create(:pre_receive_environment), repository: create(:repository, :minimal), script: "script.rb"
    assert !hook.valid?

    hook.name = "𫓧龦︐唉丂荳◎℉㐁&"
    assert hook.valid?
  end

  test "repo/script must be unique" do
    skip "https://github.com/github/github/issues/358971"

    repo = create(:repository)
    PreReceiveHook.create name: "name1", repository: repo, environment: create(:pre_receive_environment), script: "original_script.rb"
    hook = PreReceiveHook.new name: "name2", repository: repo, environment: create(:pre_receive_environment), script: "original_script.rb"
    assert !hook.valid?
    hook.script = "another_script.rb"
    assert hook.valid?
    hook.script = "original_script.rb"
    hook.repository = create(:repository, :minimal)
    assert hook.valid?

  end

  test "repo url for hook cloning in test mode" do
    skip "https://github.com/github/github/issues/358971"

    repo = create(:repository)
    hook = PreReceiveHook.create name: "name1", repository: repo, environment: create(:pre_receive_environment), script: "original_script.rb"

    assert_equal hook.repository_url, "file://#{repo.shard_path}"
  end

  test "repo url for hook cloning in production mode" do
    skip "https://github.com/github/github/issues/358971"

    repo = create(:repository)
    Rails.env.stubs(:production?).returns(true)
    GitHub.stubs(:repository_root).returns("/data/repositories")
    hook = PreReceiveHook.create name: "name1", repository: repo, environment: create(:pre_receive_environment), script: "original_script.rb"

    assert_equal hook.repository_url, "git://localhost:#{GitHub.git_daemon_port}#{repo.shard_path.sub(GitHub.repository_root, "")}"
  end

  test "repo must be updated on hook creation" do
    skip "https://github.com/github/github/issues/358971"

    repo = create(:repository, from_example: :simple)

    only = [PreReceiveEnvironmentDownloadJob, PreReceiveRepositoryUpdateJob]
    perform_enqueued_jobs(only: only) do
      PreReceiveHook.create name: "name1", repository: repo, environment: create(:pre_receive_environment), script: "original_script.rb"
    end
    assert Dir.exist?(File.join(GitHub.custom_hooks_dir, "repos", repo.id.to_s)), "Directory not checked out"
    assert File.exist?(File.join(GitHub.custom_hooks_dir, "repos", repo.id.to_s, "empty_file")), "File doesn't exist in repository"
  end

  test "repo must be updated if already checked out on hook creation" do
    skip "https://github.com/github/github/issues/358971"

    repo = create(:repository, from_example: :simple)

    only = [PreReceiveEnvironmentDownloadJob, PreReceiveRepositoryUpdateJob]
    perform_enqueued_jobs(only: only) do
      PreReceiveHook.create name: "name1", repository: repo, environment: create(:pre_receive_environment), script: "original_script.rb"
    end

    user = create(:user)
    metadata = { message: "test commit", committer: user }

    oid = repo.heads.find("master").target_oid
    commit = repo.commits.create(metadata, oid) do |files|
      files.add("my_new_file.txt", "check this out!\n")
    end
    repo.heads.find("master").update(commit.oid, user)

    only = [PreReceiveEnvironmentDownloadJob, PreReceiveRepositoryUpdateJob]
    perform_enqueued_jobs(only: only) do
      PreReceiveHook.create name: "name2", repository: repo, environment: create(:pre_receive_environment), script: "another_script.rb"
    end

    assert File.exist?(File.join(GitHub.custom_hooks_dir, "repos", repo.id.to_s, "my_new_file.txt")), "File doesn't exist in repository"
  end

  test "repo is only run on changing the repository id" do
    skip "https://github.com/github/github/issues/358971"

    repo = create(:repository, from_example: :simple)

    hook = PreReceiveHook.new
    assert_enqueued_jobs 1, only: PreReceiveRepositoryUpdateJob, queue: :pre_receive_repository_update do
      hook = PreReceiveHook.create name: "name1", repository: repo, environment: create(:pre_receive_environment), script: "original_script.rb"
    end

    assert_enqueued_jobs 0, only: PreReceiveRepositoryUpdateJob, queue: :pre_receive_repository_update do
      hook.name = "name2"
      hook.save
    end

    assert_enqueued_jobs 1, only: PreReceiveRepositoryUpdateJob, queue: :pre_receive_repository_update do
      hook.repository = create(:repository)
      hook.save
    end
  end

  test "creates an audit log entry on create" do
    events = subscribe "pre_receive_hook.create"
    hook = PreReceiveHook.create name: "name1", repository: @repo, environment: create(:pre_receive_environment), script: "original_script.rb"

    expected_payload = { pre_receive_hook: "name1", pre_receive_hook_id: hook.id, public_repo: @repo.public? }
    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "creates an audit log entry on update" do
    events = subscribe "pre_receive_hook.update"
    hook = PreReceiveHook.create name: "name1", repository: @repo, environment: create(:pre_receive_environment), script: "original_script.rb"
    hook.name = "other"
    hook.save

    expected_payload = { pre_receive_hook: "other", pre_receive_hook_id: hook.id, public_repo: @repo.public? }
    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "creates an audit log entry on destroy" do
    events = subscribe "pre_receive_hook.destroy"
    hook = PreReceiveHook.create name: "name1", repository: @repo, environment: create(:pre_receive_environment), script: "original_script.rb"
    hook.destroy

    expected_payload = { pre_receive_hook: "name1", pre_receive_hook_id: hook.id, public_repo: @repo.public? }
    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end
end
