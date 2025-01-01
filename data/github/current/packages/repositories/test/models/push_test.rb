# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class CreatingAPushByWayOfBeforeAndAfterTest < GitHub::TestCase
  include StringFromBinaryTestHelper
  include PushTestHelper

  Spokesd.share_spokesdb(self)

  fixtures do
    @mojombo  = create(:user, login: "mojombo",  plan: "medium")
    @defunkt  = create(:user, login: "defunkt",  plan: "medium")
    @pj       = create(:user, login: "pj",       plan: "medium")
    @grit     = create(:repository, name: "grit-push-test", owner: @mojombo, has_wiki: true)

    GitHub.reset_stratocaster
  end

  setup do
    example_repo :mojombo_grit, @grit

    Spokesd.enable_spokesd
    if GitHub.enterprise?
      GitHub.stubs(
        dependency_graph_enabled?: true,
        dotcom_connection_enabled?: true,
        ghe_content_analysis_enabled?: true,
      )
    end

    @message = {
      before: "4c8124ffcf4039d292442eeccabdeca5af5c5017",
      after: "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425",
      ref: "refs/heads/master",
      repository: @grit,
      pusher: @defunkt,
      pushed_at: Time.now
    }

    @push = nil
    perform_enqueued_jobs(only: ProcessEventJob) do
      trigger_push_event(
        @grit.shard_path,
        @defunkt.login,
        [["refs/heads/master", "4c8124ffcf4039d292442eeccabdeca5af5c5017", "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425"]],
        Time.now,
        perform_hydro_push_jobs: [HydroRepositoriesOnPushJob]
      )
    end

    @push = @grit.pushes.last
    reset_hydro
  end

  test "Populates push type properly" do
    push = Push.create(@message)
    assert push.reload.push_push_type?

    data = { before: GitHub::NULL_OID }.reverse_merge(@message)
    push = Push.create(data)
    assert push.reload.branch_creation_push_type?

    data = { after: GitHub::NULL_OID }.reverse_merge(@message)
    push = Push.create(data)
    assert push.reload.branch_deletion_push_type?

    push = Push.new(@message)
    push.stubs(:merge_base_commit_sha).returns("5057e76a11abd02e83b7d3d3171c4b68d9c88480")
    push.save!
    assert push.reload.force_push_push_type?

    push = Push.new(@message)
    push.set_push_type(merge_method: true)
    push.save!
    assert push.reload.pr_merge_push_type?
  end

  test "figures out all the shas involved" do
    assert_equal [
      ["06f63b43050935962f84fe54473a7c5de7977325", "tom@mojombo.com", "stub git call for Grit#heads test", "Tom Preston-Werner", false],
      ["5057e76a11abd02e83b7d3d3171c4b68d9c88480", "tom@mojombo.com", "clean up heads test", "Tom Preston-Werner", false],
      ["a47fd41f3aa4610ea527dcc1669dfdb9c15c5425", "tom@mojombo.com", "add more comments throughout", "Tom Preston-Werner", false],
    ], @push.commits_summary
  end

  test "handles refs with wide multibyte characters" do
    encoded_value = "refs/heads/🔥base"
    encoded_value2 = "refs/heads/\xF0\x9F\x94\xA5base"

    data = { ref: encoded_value }.reverse_merge(@message)

    push = Push.create(data)

    assert_equal encoded_value, push.reload.ref
    assert_multibyte_tracked_changes(push, :ref, encoded_value, encoded_value2)
  end

  context "#created?" do
    test "returns true if the push created a branch" do
      data = { before: GitHub::NULL_OID }.reverse_merge(@message)
      push = Push.create(data)
      assert push.reload.branch_creation_push_type?
      refute push.deleted?

      assert push.created?
    end
  end

  context "#deleted?" do
    test "returns true if the push deleted a branch" do
      data = { after: GitHub::NULL_OID }.reverse_merge(@message)
      push = Push.create(data)
      assert push.reload.branch_deletion_push_type?
      refute push.created?

      assert push.deleted?
    end
  end

  context "#non_fast_forward?" do
    test "uses the push_type if possible" do
      push = Push.new(@message)
      push.stubs(:merge_base_commit_sha).returns("5057e76a11abd02e83b7d3d3171c4b68d9c88480")
      push.save!
      assert push.reload.force_push_push_type?

      push.stubs(:merge_base_commit_sha).raises(RuntimeError.new("should not call gitrpc for this!"))
      assert push.non_fast_forward?
    end

    test "computes correct value when push_type is not forced" do
      push = Push.create(@message)
      assert push.reload.push_push_type?

      refute push.force_push_push_type?
      refute push.non_fast_forward?
    end
  end

  context "license_changed" do
    test "detects when a push changes a standard license file" do
      repo = create :repository, name: "repo", owner: @mojombo
      repo.license_template = "mit"
      repo.created_by_user_id = @mojombo.id
      repo.initialize_git_repository_templates

      push = Push.new repository_id: repo.id,
                      pusher_id: @mojombo.id,
                      ref: repo.default_branch,
                      after: repo.rpc.read_refs["refs/heads/#{repo.default_branch}"],
                      pushed_at: Time.now

      push.stubs(:changed_files).returns([Repositories::Push::ChangedFile.new(path: "LICENSE")])
      assert push.license_changed?
    end

    test "detects when a push changes a named license file" do
      repo = create :repository, name: "repo", owner: @mojombo
      repo.license_template = "mit"
      repo.created_by_user_id = @mojombo.id
      repo.initialize_git_repository_templates

      push = Push.new repository_id: repo.id,
                      pusher_id: @mojombo.id,
                      ref: repo.default_branch,
                      after: repo.rpc.read_refs["refs/heads/#{repo.default_branch}"],
                      pushed_at: Time.now

      push.stubs(:changed_files).returns([Repositories::Push::ChangedFile.new(path: "MIT-LICENSE")])
      assert push.license_changed?
    end

    test "detects when a push removes a license file" do
      repo = create :repository, name: "repo", owner: @mojombo
      repo.license_template = "mit"
      repo.created_by_user_id = @mojombo.id
      repo.initialize_git_repository_templates

      push = Push.new repository_id: repo.id,
                      pusher_id: @mojombo.id,
                      ref: repo.default_branch,
                      after: repo.rpc.read_refs["refs/heads/#{repo.default_branch}"],
                      pushed_at: Time.now

      push.stubs(:changed_files).returns([Repositories::Push::ChangedFile.new(path: nil, previous_path: "MIT-LICENSE")])
      assert push.license_changed?
    end

    test "detects that a license is unchanged if a push had no changed files" do
      repo = create :repository, name: "repo", owner: @mojombo
      repo.license_template = "mit"
      repo.created_by_user_id = @mojombo.id
      repo.initialize_git_repository_templates

      push = Push.new repository_id: repo.id,
                      pusher_id: @mojombo.id,
                      ref: repo.default_branch,
                      after: repo.rpc.read_refs["refs/heads/#{repo.default_branch}"],
                      pushed_at: Time.now

      push.stubs(:changed_files).returns(nil)
      push.save!
      refute RepositoryLicense.push_changed_license?(push)
    end
  end
end

class BigPushesTest < GitHub::TestCase
  include PushTestHelper

  Spokesd.share_spokesdb(self)

  fixtures do
    @mojombo = create(:user, login: "mojombo",  plan: "medium")
    @grit    = create(:repository, name: "github", owner: @mojombo, from_example: :mojombo_grit)

    message =  {
      before: "5057e76a11abd02e83b7d3d3171c4b68d9c88480",
      after: "86264f45ff4bcd3da195f5c83f7e414ed4a71628",
      ref: "refs/heads/master",
      repository: @grit,
      pusher: @mojombo,
      pushed_at: Time.now
    }


    GitHub.reset_stratocaster
    perform_enqueued_jobs(only: ProcessEventJob) do
      trigger_push_event(
        @grit.shard_path,
        @mojombo.login,
        [["refs/heads/master", "5057e76a11abd02e83b7d3d3171c4b68d9c88480", "86264f45ff4bcd3da195f5c83f7e414ed4a71628"]],
        Time.now,
        perform_hydro_push_jobs: [HydroRepositoriesOnPushJob]
      )
    end
    @event = GitHub.stratocaster_store.last.freeze
  end

  test "only saves the first 20 shas in the event" do
    assert_equal 20, @event.payload["commits"].size
  end

  test "knows how many shas are actually involved in the event" do
    assert_equal 39, @event.payload["size"]
  end

  test "knows how many distinct shas are actually involved in the event" do
    assert_equal 0, @event.payload["distinct_size"]
  end
end

class ChangedFilesTest < GitHub::TestCase
  include PushTestHelper

  Spokesd.share_spokesdb(self)

  setup do
    Spokesd.enable_spokesd
    @repo = create(:repository, from_example: :initial_commit_ruby_library)
  end

  test "detects files added between oids" do
    push = push_changes(repository: @repo, changes: { path: "README" })
    assert_equal 1, push.changed_files.count

    changed_file = push.changed_files.first
    assert changed_file.addition?
    assert_equal "README", push.changed_files.first.path
  end

  test "detects files removed between oids" do
    push = push_changes(repository: @repo, changes: { path: "README.md", new_path: nil })
    assert_equal 1, push.changed_files.count

    changed_file = push.changed_files.first
    assert changed_file.deletion?
    assert_equal "README.md", push.changed_files.first.path
  end

  test "detects files renamed between oids" do
    push = push_changes(repository: @repo, changes: { path: "README.md", new_path: "README" })
    assert_equal 1, push.changed_files.count

    changed_file = push.changed_files.first
    assert changed_file.renaming?
    assert_equal "README", changed_file.path
    assert_equal "README.md", changed_file.previous_path
  end

  context "when decompose_renames is true" do
    test "detects renamed files as an addition and deletion" do
      push = push_changes(repository: @repo, changes: { path: "README.md", new_path: "README" })
      changed_files = push.changed_files(decompose_renames: true)
      assert_equal 2, changed_files.count

      removed_file = changed_files.last
      assert removed_file.deletion?
      assert_equal "README.md", removed_file.path
      assert_nil removed_file.previous_path

      added_file = changed_files.first
      assert added_file.addition?
      assert_equal "README", added_file.path
      assert_nil added_file.previous_path
    end
  end
end

class DependabotConfigChangedTest < GitHub::TestCase
  include DogstatsTestHelpers
  include PushTestHelper

  Spokesd.share_spokesdb(self)

  setup do
    Spokesd.enable_spokesd

    @repo = create(:repository, from_example: :simple)
  end

  context "dependabot_config_changed?" do
    test "is true for config change on default branch" do
      push = push_changes(repository: @repo, changes: { path: ".github/dependabot.yml" })
      assert push.dependabot_config_changed?
      assert_dogstats_timing "push.dependabot_config_changed"
    end

    test "is false for config change on non-default branch" do
      push = push_changes(repository: @repo, changes: { path: ".github/dependabot.yml" }, branch_name: "pr-1", create_branch: true)
      refute push.dependabot_config_changed?
      assert_dogstats_timing 0, "push.dependabot_config_changed"
    end

    test "is false for non-config change" do
      push = push_changes(repository: @repo, changes: { path: "README.md" })
      refute push.dependabot_config_changed?
      assert_dogstats_timing "push.dependabot_config_changed"
    end

    test "is false for empty push" do
      push = push_changes(repository: @repo, changes: [])
      refute push.dependabot_config_changed?
      assert_dogstats_timing "push.dependabot_config_changed"
    end
  end
end

class DetectingChangedDependencyManifestFilesTest < GitHub::TestCase
  include PushTestHelper
  include HydroTestHelpers

  Spokesd.share_spokesdb(self)

  setup do
    Spokesd.enable_spokesd

    @repo = create(:repository, from_example: :initial_commit_ruby_library)

    if GitHub.enterprise?
      GitHub.stubs(
        dependency_graph_enabled?: true,
        dotcom_connection_enabled?: true,
        ghe_content_analysis_enabled?: true,
      )
    end
  end

  context "dependency_manifest_changed?" do
    %w(Gemfile Gemfile.lock package.json package-lock.json).each do |path|
      test "is true if changed files include #{path}" do
        push = push_changes(repository: @repo, changes: { path: path })
        assert push.dependency_manifest_changed?
      end
    end

    test "is false for non-manifest changes" do
      push = push_changes(repository: @repo, changes: { path: "README" })
      refute push.dependency_manifest_changed?
    end
  end


end
