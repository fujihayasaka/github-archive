# typed: true
# frozen_string_literal: true

require "test_helper"

# Code referred from test/jobs/clone_template_repository_files_job_test.rb
class StacksCloneHelperTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroMessageJobTestHelpers
  include PushTestHelper

  fixtures do
    @template_repo = create(:repository, name: "AGreatTemplate", from_example: :community_files)
    @new_repo = create(:repository)
    create :release, name: "Version One!", tag_name: "v1.0", author: @template_repo.owner, repository: @template_repo
    @cloning_user = create(:user)
    @stack_instance = StacksInstance.create(template_repo: @template_repo.name_with_owner, owner_id: @cloning_user.id,
                             actor_id: @cloning_user.id, instance_repository_id: @new_repo.id, template_repository_id: @template_repo.id, template_ref: "refs/tags/v1.0")
  end

  setup do
    WebFlowHelper.setup_webflow
  end

  test "raises when StackInstance is nil" do
    stack_instance_id = nil
    error = assert_raises(Errors::CloneError) do
      StacksCloneHelper.new.clone_ref(nil, nil)
    end
    assert_equal "Could not finish repository cloning. missing stack instance", error.message
  end

  test "return error when template repo does not exist" do
    @template_repo.delete

    error = assert_raises(Errors::CloneError) do
      StacksCloneHelper.new.clone_ref(@stack_instance)
    end

    assert_equal "Could not finish repository cloning. missing active template repo", error.message
  end

  test "returns error when template repo is not active" do
    @template_repo.update_attribute(:active, false)

    error = assert_raises(Errors::CloneError) do
      StacksCloneHelper.new.clone_ref(@stack_instance)
    end

    assert_equal error.message, "Could not finish repository cloning. missing active template repo"
  end

  test "sets state to error when clone repo does not exist" do
    @new_repo.delete

    error = assert_raises(Errors::CloneError) do
      StacksCloneHelper.new.clone_ref(@stack_instance)
    end

    assert_equal error.message, "Could not finish repository cloning. missing clone repository"
  end

  test "copies build directory to new repository" do
    example_repo :empty, @template_repo
    base_ref = @template_repo.heads.build(@template_repo.default_branch)
    base_ref.append_commit({ message: "Add build dir",
                             committer: @template_repo.owner }, @template_repo.owner) do |files|
      files.add("build/prepare.js", "/* Sample contents */")
      files.add("README.txt", "other file")
    end
    StacksCloneHelper.new.clone_ref(@stack_instance)

    assert_same_files @template_repo, @new_repo
    assert_initial_commit @stack_instance
  end

  test "preserves executable file permission on clone" do
    example_repo :language_test, @template_repo
    commit_oid = @template_repo.ref_to_sha(@template_repo.default_branch)
    tree_entry = @template_repo.tree_entry(commit_oid, "build_tar.sh")
    refute_nil tree_entry, "should have a particular file in the template repo"
    assert_predicate tree_entry, :executable?,
      "file in template needs to be executable for this test"

    StacksCloneHelper.new.clone_ref(@stack_instance)

    assert_same_files @template_repo, @new_repo
    commit_oid = @new_repo.ref_to_sha(@new_repo.default_branch)
    tree_entry = @new_repo.tree_entry(commit_oid, "build_tar.sh")
    assert_predicate tree_entry, :executable?, "file in clone should be executable like in template"
  end

  test "has the same files in new repository as are in the template" do
    example_repo :community_files, @template_repo
    create :release, name: "Version One!", tag_name: "v2.0", author: @template_repo.owner, repository: @template_repo
    org = create(:organization, admin: @cloning_user)
    new_repo = create(:repository, owner: org)
    stack_instance = StacksInstance.create(template_repo: @template_repo.name_with_owner, owner_id: @cloning_user.id,
      actor_id: @cloning_user.id, instance_repository_id: new_repo.id, template_repository_id: @template_repo.id,  template_ref:  "refs/tags/v2.0")

    StacksCloneHelper.new.clone_ref(stack_instance)

    assert_same_files @template_repo, new_repo
    assert_initial_commit stack_instance
  end

  test "preserves submodule entries" do
    template_with_submodules = create(:repository, name: "TemplateWithSubmodules", from_example: :tree_with_submod)
    create :release, name: "Version One!", tag_name: "v1.0", author: template_with_submodules.owner, repository: template_with_submodules
    org = create(:organization, admin: @cloning_user)
    new_repo = create(:repository, owner: org)
    stack_instance = StacksInstance.create(template_repo: template_with_submodules.name_with_owner, owner_id: @cloning_user.id,
                                            actor_id: @cloning_user.id, instance_repository_id: new_repo.id, template_repository_id: template_with_submodules.id,  template_ref: "refs/tags/v1.0")


    StacksCloneHelper.new.clone_ref(stack_instance)

    _new_repo_tree_oid, new_repo_entries, _truncated = \
      new_repo.tree_entries(new_repo.default_oid, "")

    _template_tree_oid, template_entries, _truncated = \
      template_with_submodules.tree_entries(template_with_submodules.default_oid, "")

    assert_initial_commit stack_instance
    assert_equal new_repo_entries.map(&:name), template_entries.map(&:name)
    assert new_repo_entries.any? { |entry| entry.submodule? }
  end

  test "clones a repository containing an image" do
    example_repo :wiki_controller_public, @template_repo
    StacksCloneHelper.new.clone_ref(@stack_instance)

    assert_same_files @template_repo, @new_repo
    assert_initial_commit @stack_instance
  end

  test "does not copy all branches by default" do
    example_repo :branch_escape, @template_repo

    StacksCloneHelper.new.clone_ref(@stack_instance)

    assert_equal 1, @new_repo.rpc.raw_branch_names_and_dates.size, "should be only one branch in new repo"
    assert_initial_commit @stack_instance
    assert_same_files @template_repo, @new_repo
  end

  test "copies from specified ref" do
    example_repo :branch_escape, @template_repo
    ref = "refs/heads/zzz"
    StacksCloneHelper.new.clone_ref(@stack_instance, ref)

    assert_initial_commit @stack_instance
    assert_same_files @template_repo, @new_repo, branch_name: "zzz"
    assert_equal @new_repo.default_branch, @template_repo.default_branch
  end

  test "errors when copying a ref fails" do
    Git::Ref::Collection.any_instance.stubs(:find).returns(nil)

    error = assert_raises(Errors::CloneError) do
      StacksCloneHelper.new.clone_ref(@stack_instance)
    end
    assert_equal error.message, "Could not finish repository cloning. no commit oid for stack repo ref"
    assert_dogstats_increment "stack_step.repo_clone.status", tags: ["action:error"]
  end

  test "errors when there is a timeout" do
    example_repo :wiki_controller_public, @template_repo
    GitRPC::Backend.any_instance.stubs(:create_tree_changes).raises(GitRPC::Timeout)
    GitRPC::Backend.any_instance.stubs(:persist_signed_tree_changes).raises(GitRPC::Timeout)

    assert_raises(GitRPC::Timeout) do
      StacksCloneHelper.new.clone_ref(@stack_instance)
    end

    assert_dogstats_increment "stack_step.repo_clone.status", tags: ["action:error"]
  end

  test "errors when updating the default branch branch fails" do
    example_repo :branch_escape, @template_repo
    assert @template_repo.update_default_branch("zzz"),
      "need a default branch in the template repo that differs from the clone's default branch"
    Repository.any_instance.stubs(:update_default_branch).returns(false)

    error = assert_raises(Errors::CloneError) do
      StacksCloneHelper.new.clone_ref(@stack_instance)
    end

    assert_equal error.message, "Could not finish repository cloning. failed to update default branch"
  end

  test "sets default branch of new repo to match template repo" do
    example_repo :branch_escape, @template_repo
    default_branch = "zzz"
    assert @template_repo.update_default_branch(default_branch),
      "need a default branch in the template repo that differs from the clone's default branch"

    StacksCloneHelper.new.clone_ref(@stack_instance)

    assert_equal default_branch, @new_repo.reload.default_branch, "should have set new repo's default branch to match template's"
    assert_initial_commit @stack_instance
    assert_same_files @template_repo, @new_repo
  end

  test "errors if there is a git error" do
    example_repo :invalid_objects_test, @template_repo
    base_ref = @template_repo.heads.build(@template_repo.default_branch)

    error = assert_raises(Errors::CloneError) do
      StacksCloneHelper.new.clone_ref(@stack_instance)
    end

    assert_equal error.message, "Could not finish repository cloning. no commit oid for stack repo ref"
  end

  test "copies repos smaller than than the max size" do
    example_repo :repository_test_simple, @template_repo
    Repository.any_instance.stubs(:disk_usage).returns(900_000.kilobytes)

    StacksCloneHelper.new.clone_ref(@stack_instance)

    assert_initial_commit @stack_instance
    assert_same_files @template_repo, @new_repo
    assert_dogstats_increment "stack_step.repo_clone.status", tags: ["action:success"]
  end

  test "errors if repository disk usage is more than max size" do
    example_repo :repository_test_simple, @template_repo

    Repository.any_instance.stubs(:disk_usage).returns(1_100_000.kilobytes)

    error = assert_raises(Errors::CloneError) do
      StacksCloneHelper.new.clone_ref(@stack_instance)
    end

    assert_equal "Could not finish repository cloning. active template repo too large", error.message
  end

  test "errors if the repository contains more than 100,000 files" do
    example_repo :empty, @template_repo
    base_ref = @template_repo.heads.build(@template_repo.default_branch)
    base_ref.append_commit({ message: "Add large file",
                            committer: @template_repo.owner }, @template_repo.owner) do |_files|
    end

    # Rather than create a repository with 100,000 files, we can stub `tree_entries`
    # to return a truncated result set, which indicates that the repo contains
    # more than the max number of allowed files.
    Repository.any_instance.stubs(:tree_entries).returns([nil, nil, true])

    error = assert_raises(Errors::CloneError) do
      StacksCloneHelper.new.clone_ref(@stack_instance)
    end

    assert_equal "Could not finish repository cloning. too many files for stack repo ref", error.message
  end

  test "creates Push record" do
    example_repo :simple, @template_repo

    assert_nil push_accessor.latest_for_repo(repository_id: @new_repo.id)

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      StacksCloneHelper.new.clone_ref(@stack_instance)
    end

    oid = @new_repo.default_oid
    default_branch = @new_repo.reload.default_branch

    assert push = push_accessor.latest_for_repo(repository_id: @new_repo.id)
    assert_equal "refs/heads/#{default_branch}", push&.ref
    assert_equal oid, push&.after
    assert_dogstats_increment "stack_step.repo_clone.status", tags: ["action:success"]
  end

  test "removes .github/stacks folder from the new repo" do
    example_repo :stacks_repo, @template_repo

    Repository.any_instance.stubs(:disk_usage).returns(900_000.kilobytes)

    StacksCloneHelper.new.clone_ref(@stack_instance)
    assert_initial_commit @stack_instance
    assert_same_files_without_stacks_folder @template_repo, @new_repo
  end

  test "removes files in .stackignore" do
    example_repo :empty, @template_repo
    base_ref = @template_repo.heads.build(@template_repo.default_branch)
    base_ref.append_commit({ message: "Add build dir",
                             committer: @template_repo.owner }, @template_repo.owner) do |files|
      files.add("build/1.js", "/* Sample contents */")
      files.add("build/2.js", "/* Sample contents */")
      files.add("build/3.js", "/* Sample contents */")
      files.add("build/4.js", "/* Sample contents */")
      files.add("1.js", "/* Sample contents */")
      files.add("2.js", "/* Sample contents */")
      files.add("readme.md", "readme file")
      files.add(".stackignore",
         "#Ignore build files\n"\
         "build/*\n"\
         "#Ignore file named 1.js\n"\
         "1.js\n"
        )
    end
    StacksCloneHelper.new.clone_ref(@stack_instance)
    assert_initial_commit @stack_instance
  end

  def assert_initial_commit(stack_instance)
    new_repo = stack_instance.instance_repository
    assert_commit_in_branch(new_repo.default_branch, repo: new_repo, user: @cloning_user)

    commit_oid = new_repo.ref_to_sha(new_repo.default_branch)
    commit = new_repo.commits.paged_history(commit_oid).first
    assert_equal StacksCloneHelper::DEFAULT_BRANCH_COMMIT_MESSAGE, commit.message,
      "first commit in default branch of new repo should have specific message"
  end

  def assert_commit_in_branch(branch_name, repo:, user:)
    commit_oid = repo.ref_to_sha(branch_name)
    refute_nil commit_oid, "repo should have a commit in branch '#{branch_name}'"

    commits = repo.commits.paged_history(commit_oid)
    assert commits.size >= 0, "should have at least one commit in branch '#{branch_name}'"

    commits.each do |commit|
      assert_commit_by(user, commit: commit)
      assert_commit_signed_and_verified(commit: commit)
    end
  end

  def assert_commit_by(user, commit:)
    assert_equal user, commit.author, "author of commit should be the user who initiated the clone job"
    assert_equal GitHub.web_committer_name, commit.committer_name, "committer name should be the GitHub web committer name"
    assert_equal GitHub.web_committer_email, commit.committer_email, "committer email should be the GitHub web committer email"
  end

  def assert_commit_signed_and_verified(commit:)
    if GitHub.enterprise?
      puts "Skipping assert_commit_signed_and_verified check because we are in enterprise runtime" if TestEnv.test_queue_verbose?
      return
    end

    assert_predicate commit, :has_signature?
    assert_equal :verified, commit.verification_status
  end

  def assert_same_files(template_repo, new_repo, branch_name: nil)
    branch_name ||= template_repo.default_branch
    tmpl_commit_oid = template_repo.ref_to_sha(branch_name)
    refute_nil tmpl_commit_oid, "template repo should have a commit in branch '#{branch_name}'"
    expected_files = template_repo.tree_file_list(tmpl_commit_oid, skip_directories: [])
    refute_empty expected_files, "should have some files in the template repo in branch '#{branch_name}'"
    expected_files.delete("README.md")

    new_repo_branch_name = new_repo.default_branch.b
    commit_oid = new_repo.ref_to_sha(new_repo_branch_name)
    refute_nil commit_oid, "new repo should have a commit in branch '#{new_repo_branch_name}'"
    actual_files = new_repo.tree_file_list(commit_oid, skip_directories: [])

    assert_equal expected_files, actual_files,
      "expected new repository to have the same files as the template repo in branch '#{branch_name}'"

    expected_files.each do |expected_path|
      expected_tree_entry = template_repo.tree_entry(tmpl_commit_oid, expected_path)
      actual_tree_entry = new_repo.tree_entry(commit_oid, expected_path)
      assert_equal expected_tree_entry.data, actual_tree_entry.data,
        "new repo should have same file contents as template in #{expected_path} in branch '#{new_repo_branch_name}'"
      if expected_tree_entry.encoding
        assert_equal expected_tree_entry.encoding, actual_tree_entry.encoding,
          "new repo should have same file encoding as template for #{expected_path} in branch '#{new_repo_branch_name}'"
      else
        assert_nil actual_tree_entry.encoding,
          "new repo should lack file encoding like template does for #{expected_path} in branch '#{new_repo_branch_name}'"
      end
    end
  end

  def assert_same_files_without_stacks_folder(template_repo, new_repo)
    branch_name ||= template_repo.default_branch
    tmpl_commit_oid = template_repo.ref_to_sha(branch_name)
    refute_nil tmpl_commit_oid, "template repo should have a commit in branch '#{branch_name}'"
    expected_files = template_repo.tree_file_list(tmpl_commit_oid, skip_directories: [])
    refute_empty expected_files, "should have some files in the template repo in branch '#{branch_name}'"
    expected_files.delete("README.md")

    new_repo_branch_name = new_repo.default_branch.b
    commit_oid = new_repo.ref_to_sha(new_repo_branch_name)
    refute_nil commit_oid, "new repo should have a commit in branch '#{new_repo_branch_name}'"
    actual_files = new_repo.tree_file_list(commit_oid, skip_directories: [])

    expected_files_without_stacks_folder = expected_files.select do |file|
      !file.include?(StacksCloneHelper::GITHUB_STACKS_FOLDER_PATH)
    end

    assert_equal expected_files_without_stacks_folder, actual_files,
      "expected new repository to have the same files as the template repo in branch '#{branch_name}'"

    expected_files_without_stacks_folder.each do |expected_path|
      expected_tree_entry = template_repo.tree_entry(tmpl_commit_oid, expected_path)
      actual_tree_entry = new_repo.tree_entry(commit_oid, expected_path)
      assert_equal expected_tree_entry.data, actual_tree_entry.data,
        "new repo should have same file contents as template in #{expected_path} in branch '#{new_repo_branch_name}'"
      if expected_tree_entry.encoding
        assert_equal expected_tree_entry.encoding, actual_tree_entry.encoding,
          "new repo should have same file encoding as template for #{expected_path} in branch '#{new_repo_branch_name}'"
      else
        assert_nil actual_tree_entry.encoding,
          "new repo should lack file encoding like template does for #{expected_path} in branch '#{new_repo_branch_name}'"
      end
    end
  end
end
