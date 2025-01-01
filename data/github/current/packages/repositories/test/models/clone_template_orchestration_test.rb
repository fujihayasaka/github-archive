# typed: true
# frozen_string_literal: true

require "test_helper"

class CloneTemplateOrchestrationTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @template_repo = create(:repository, name: "AGreatTemplate", template: true, from_example: :community_files)
    @owner = create(:user)
    @name = "my-new-repo"
    @description = "This will be a fun project."
  end

  setup do
    WebFlowHelper.setup_webflow
  end

  context "synchronous orchestration steps" do
    test "errors when given a non-empty new repository" do
      new_repo = create(:repository, owner: @owner, from_example: :simple)
      orchestration = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: @owner, new_repository: new_repo)
      assert_no_difference("Repository.count") do
        orchestration.execute
        refute orchestration.succeeded?
      end

      assert_equal "#{new_repo.name_with_owner} already has content.", orchestration.errors.first.message
    end

    test "errors when actor cannot access the template repository" do
      private_template = create(:private_repository, template: true, from_example: :simple)
      orchestration = RepositoryOrchestration.clone_template(template_repository: private_template, actor: @owner, owner: @owner,
                                           name: @name, visibility: "public",
                                           description: @description)

      assert_no_difference("Repository.count") do
        orchestration.execute
        refute orchestration.succeeded?
      end

      assert_equal "template repository not found.", orchestration.errors.first.message
    end

    test "errors when the template repository is nil" do
      orchestration = RepositoryOrchestration.clone_template(template_repository: nil, actor: @owner, owner: @owner,
                                           name: @name, visibility: "public",
                                           description: @description)
      orchestration.execute
      refute orchestration.succeeded?

      assert_equal "template repository not found.", orchestration.errors.first.message
    end

    test "errors when template repository is disabled" do
      template = create(:repository, template: true)
      template.access.disable("size", create(:staff_admin_user))
      orchestration = RepositoryOrchestration.clone_template(template_repository: template, actor: @owner, owner: @owner,
                                           name: @name, visibility: "public",
                                           description: @description)

      assert_no_difference("Repository.count") do
        orchestration.execute
        refute orchestration.succeeded?
      end

      assert_equal "#{template.name_with_owner} has been disabled and cannot be used as a template.", orchestration.errors.first.message
    end

    test "errors when owner is over repository limit" do
      create_list(:private_repository, 2, owner: @owner, force_user_owned: true)
      count = Repository.where(owner: @owner).count
      limiter = RepositoryLimit.new(@owner)
      limiter.override(soft: count - 1, hard: count)
      orchestration = RepositoryOrchestration.clone_template(
        template_repository: @template_repo,
        actor: @owner,
        owner: @owner,
        name: @name,
        visibility: "public",
        description: @description
      )

      if limiter.enabled?
        assert_no_difference("Repository.count") do
          orchestration.execute
          refute orchestration.succeeded?
        end

        assert_equal "Repository Owner is over repository limit.", orchestration.errors.first.message
      else
        assert_difference("Repository.count", 1) do
          orchestration.execute
          assert orchestration.running?
        end
      end
    end

    test "uses given new repository when it's empty" do
      new_repo = create(:repository, owner: @owner)
      orchestration = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: @owner, new_repository: new_repo)

      assert_no_difference("Repository.count") do
        perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
          orchestration.execute
        end
      end

      assert orchestration.reload.succeeded?
      assert_equal new_repo, orchestration.repository
    end

    test "errors when template repository is empty" do
      template = create(:repository, template: true)
      orchestration = RepositoryOrchestration.clone_template(template_repository: template, actor: @owner, owner: @owner,
                                           name: @name, visibility: "public",
                                           description: @description)

      assert_no_difference("Repository.count") do
        orchestration.execute
      end

      assert_equal "#{template.name_with_owner} is empty.", orchestration.errors.first.message
    end

    test "creates a new repository" do
      orchestration = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: @owner, owner: @owner, name: @name,
                                           visibility: "public", description: @description)

      assert_difference("@owner.public_repositories.count") do
        perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
          orchestration.execute
        end
      end

      assert orchestration.reload.succeeded?
      refute_nil orchestration.repository
      assert_equal @name, orchestration.repository&.name
      assert_equal @description, orchestration.repository&.description
      assert_equal orchestration.repo_clone, RepositoryClone.for_clone_repo(orchestration.repository).first
    end

    test "creates a new repository from an organization's template" do
      org = create(:organization)
      org_tmpl_repo = create(:repository, owner: org, template: true, from_example: :community_files)
      orchestration = RepositoryOrchestration.clone_template(template_repository: org_tmpl_repo, actor: @owner, owner: @owner, name: @name,
                                           visibility: "public", description: @description)

      assert_difference("@owner.public_repositories.count") do
        perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
          orchestration.execute
        end
      end

      assert orchestration.reload.succeeded?
      refute_nil orchestration.repository
      assert_equal @name, orchestration.repository&.name
      assert_equal @description, orchestration.repository&.description
    end

    test "creates a new repository in an organization" do
      org = create(:organization, admin: @owner)
      orchestration = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: @owner, owner: org, name: @name,
                                           visibility: "public", description: @description)

      assert_difference("org.public_repositories.count") do
        perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
          orchestration.execute
        end
      end

      assert orchestration.reload.succeeded?
      refute_nil orchestration.repository
      assert_equal @name, orchestration.repository&.name
      assert_equal @description, orchestration.repository&.description
    end

    test "sets error when user is not allowed to clone repository in given owner" do
      rando_org = create(:organization)
      orchestration = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: @owner, owner: rando_org,
                                           name: @name, visibility: "public",
                                           description: @description)

      assert_no_difference("Repository.count") do
        orchestration.execute
      end

      refute orchestration.succeeded?
      assert_equal "#{@owner} does not have permission to create a repository owned by #{rando_org}", orchestration.errors.first.message
    end

    test "displays create orchestration error" do
      User.any_instance.stubs(:deleted?).returns(true)
      orchestration = RepositoryOrchestration.clone_template(
        template_repository: @template_repo,
        actor: @owner,
        owner: @owner,
        name: @name,
        visibility: "public",
        description: @description
      )

      assert_no_difference("Repository.count") do
        orchestration.execute
      end

      refute orchestration.succeeded?
      assert_equal "Repository Owner is being deleted, so new repository cannot be created.", orchestration.errors.first.message
    end

    test "sets error when repository fails to save" do
      orchestration = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: @owner, owner: @owner,
                                           name: "following", visibility: "public",
                                           description: @description)

      assert_no_difference("Repository.count") do
        orchestration.execute
      end

      refute orchestration.succeeded?
      assert_equal "Name is reserved", orchestration.errors.first.message
    end

    test "sets error when given template repo is not a template" do
      non_template_repo = create(:repository, template: false)
      orchestration = RepositoryOrchestration.clone_template(template_repository: non_template_repo, actor: @owner, owner: @owner,
                                           name: @name, visibility: "public",
                                           description: @description)

      assert_no_difference("Repository.count") do
        orchestration.execute
      end

      refute orchestration.succeeded?
      assert_equal "#{non_template_repo.nwo} is not a template repository.", orchestration.errors.first.message
    end

    test "sets error when clone creation fails" do
      CreateRepositoryOrchestration.any_instance.stubs(:running?).returns(false)
      CreateRepositoryOrchestration.any_instance.stubs(:error_message).returns("it broke")

      orchestration = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: @owner, owner: @owner,
                                           name: @name, visibility: "public",
                                           description: @description)

      assert_nothing_raised do
        orchestration.execute
      end

      refute orchestration.succeeded?

      assert_equal "create orchestration ID: #{orchestration.create_orchestration.id} failed: it broke", orchestration.error_message
    end

    test "sets error when repo clone record does not save" do
      orchestration = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: @owner, owner: @owner,
                                       name: @name, visibility: "public", description: @description)

      RepositoryClone.any_instance.stubs(:save).returns(false)
      RepositoryClone.any_instance.stubs(:errors).returns(stub(full_messages: ["o no", "it broke"]))

      assert_nothing_raised do
        orchestration.execute
      end

      refute orchestration.succeeded?

      assert_equal "o no, it broke", orchestration.error_message
    end
  end

  context "asynchronous orchestration steps" do
    test "raises when RepositoryClone doesn't exist for background job" do
      orchestration = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: @owner, owner: @owner,
        name: @name, visibility: "public", description: @description)

      # prevent the clone record from saving
      RepositoryClone.any_instance.stubs(:save).returns(true)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        assert_nothing_raised do
          orchestration.execute
        end
      end

      refute orchestration.succeeded?
    end

    # https://github.com/github/github/issues/117191
    test "copies build directory to new repository" do
      template = create(:repository, template: true, from_example: :empty)
      base_ref = template.heads.build(template.default_branch)
      base_ref.append_commit({ message: "Add build dir",
                               committer: template.owner }, template.owner) do |files|
        files.add("build/prepare.js", "/* Sample contents */")
        files.add("README.txt", "other file")
      end
      cloning_user = create(:user)
      new_repo = create(:repository, owner: cloning_user)

      orchestration = RepositoryOrchestration.clone_template(template_repository: template, actor: cloning_user,
        new_repository: new_repo)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        orchestration.execute
      end

      assert orchestration.reload.succeeded?
      assert_equal "finished", orchestration.repo_clone.reload.state
      assert_same_files template, new_repo
      assert_initial_commit orchestration.repo_clone
    end

    # https://github.com/github/community-and-developer-support/issues/2186#issuecomment-507508535
    test "preserves executable file permission on clone" do
      template = create(:repository, template: true, from_example: :language_test)
      commit_oid = template.ref_to_sha(template.default_branch)
      tree_entry = template.tree_entry(commit_oid, "build_tar.sh")
      refute_nil tree_entry, "should have a particular file in the template repo"
      assert_predicate tree_entry, :executable?,
        "file in template needs to be executable for this test"
      new_repo = create(:repository)

      orchestration = RepositoryOrchestration.clone_template(template_repository: template, actor: new_repo.owner,
        new_repository: new_repo)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        orchestration.execute
      end

      assert orchestration.reload.succeeded?
      assert_equal "finished", orchestration.repo_clone.reload.state
      assert_same_files template, new_repo
      commit_oid = new_repo.ref_to_sha(new_repo.default_branch)
      tree_entry = new_repo.tree_entry(commit_oid, "build_tar.sh")
      assert_predicate tree_entry, :executable?, "file in clone should be executable like in template"
    end

    test "has the same files in new repository as are in the template" do
      cloning_user = create(:user)
      org = create(:organization, admin: cloning_user)
      new_repo = create(:repository, owner: org)

      orchestration = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: cloning_user,
        new_repository: new_repo)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        orchestration.execute
      end

      assert orchestration.reload.succeeded?
      assert_equal "finished", orchestration.repo_clone.reload.state
      assert_same_files @template_repo, new_repo
      assert_initial_commit orchestration.repo_clone
    end

    # https://github.com/github/github/issues/118751
    test "preserves submodule entries" do
      template_with_submodules = create(:repository, name: "TemplateWithSubmodules", template: true, from_example: :tree_with_submod)
      cloning_user = create(:user)
      org = create(:organization, admin: cloning_user)
      new_repo = create(:repository, owner: org)

      orchestration = RepositoryOrchestration.clone_template(template_repository: template_with_submodules, actor: cloning_user,
        new_repository: new_repo)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        orchestration.execute
      end
      assert orchestration.reload.succeeded?

      _new_repo_tree_oid, new_repo_entries, _truncated = \
        new_repo.tree_entries(new_repo.default_oid, "")

      _template_tree_oid, template_entries, _truncated = \
        template_with_submodules.tree_entries(template_with_submodules.default_oid, "")

      assert_equal "finished", orchestration.repo_clone.reload.state
      assert_initial_commit orchestration.repo_clone
      assert_equal new_repo_entries.map(&:name), template_entries.map(&:name)
      assert new_repo_entries.any? { |entry| entry.submodule? }
    end

    test "fails when repo clone can't be set to finished state" do
      new_repo = create(:repository)
      RepositoryClone.any_instance.stubs(:save).returns(false)

      orchestration = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: @owner,
        new_repository: new_repo)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        assert_nothing_raised do
          orchestration.execute
        end
      end

      assert orchestration.reload.failed?
    end

    test "clones a repository containing an image" do
      template_repo = create(:repository, template: true, from_example: :wiki_controller_public)
      new_repo = create(:repository)

      orchestration = RepositoryOrchestration.clone_template(template_repository: template_repo, actor: new_repo.owner,
        new_repository: new_repo)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        orchestration.execute
      end

      assert orchestration.reload.succeeded?
      assert_equal "finished", orchestration.repo_clone.reload.state
      assert_same_files template_repo, new_repo
      assert_initial_commit orchestration.repo_clone
    end

    test "does not copy all branches by default" do
      template_repo = create(:repository, template: true, from_example: :branch_escape)
      new_repo = create(:repository)

      orchestration = RepositoryOrchestration.clone_template(template_repository: template_repo, actor: new_repo.owner,
        new_repository: new_repo)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        orchestration.execute
      end

      assert orchestration.reload.succeeded?
      assert_equal "finished", orchestration.repo_clone.reload.state
      assert_equal 1, new_repo.rpc.raw_branch_names_and_dates.size,
        "should be only one branch in new repo"
      assert_initial_commit orchestration.repo_clone
      assert_same_files template_repo, new_repo
    end

    test "copies all branches when specified" do
      template_repo = create(:repository, template: true, from_example: :branch_escape)
      new_repo = create(:repository)

      orchestration = RepositoryOrchestration.clone_template(template_repository: template_repo, actor: new_repo.owner,
        new_repository: new_repo, copy_branches: true)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        orchestration.execute
      end

      assert orchestration.reload.succeeded?
      assert_equal "finished", orchestration.repo_clone.reload.state
      assert new_repo.rpc.raw_branch_names_and_dates.size > 1,
        "should be more than one branch in new repo"
      assert_initial_commit orchestration.repo_clone
      assert_same_files template_repo, new_repo, branch_name: "master"
      assert_same_files template_repo, new_repo, branch_name: "zzz"
      assert_commit_in_branch "zzz", repo: new_repo, user: orchestration.repo_clone.cloning_user
    end

    test "fails copy_branches when org rules are violated" do
      user = create(:user)
      org = create(:organization, admin: user, plan: "business_plus")
      ruleset = create(:repository_ruleset, :targets_all_branches, :targets_all_repos, source: org)
      create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "required_status_checks",
        parameters: { strict_required_status_checks_policy: false, required_status_checks: [{ context: "somecontext" }] })

      template_repo = create(:repository, owner: org, template: true, from_example: :branch_escape)
      new_repo = create(:repository, owner: org)

      orchestration = RepositoryOrchestration.clone_template(template_repository: template_repo, actor: user,
        new_repository: new_repo, copy_branches: true)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        orchestration.execute
      end

      assert orchestration.reload.skipped?
      assert_equal "error", orchestration.repo_clone.reload.state
      assert_equal "rule_violations", orchestration.repo_clone.error_reason_code
    end

    test "errors when copying a branch fails" do
      new_repo = create(:repository)

      Git::Ref::Collection.any_instance.stubs(:find).returns(nil)

      orchestration = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: new_repo.owner, new_repository: new_repo)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        assert_nothing_raised do
          orchestration.execute
        end
      end

      assert orchestration.reload.failed?
      assert_equal "error", orchestration.repo_clone.reload.state
      assert_equal "no_commit_oid", orchestration.repo_clone.error_reason_code
    end

    test "errors when there is a timeout" do
      template_repo = create(:repository, template: true, from_example: :wiki_controller_public)
      new_repo = create(:repository)

      GitRPC::Backend.any_instance.stubs(:create_tree_changes).raises(GitRPC::Timeout)
      GitRPC::Backend.any_instance.stubs(:persist_signed_tree_changes).raises(GitRPC::Timeout)

      orchestration = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: new_repo.owner, new_repository: new_repo)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        assert_raises(GitRPC::Error) do
          orchestration.execute
        end
      end

      refute orchestration.reload.succeeded?
      assert_equal "error", orchestration.repo_clone.reload.state
      assert_equal "gitrpc_exception", orchestration.repo_clone.error_reason_code
    end

    test "errors when updating the default branch branch fails" do
      template_repo = create(:repository, template: true, from_example: :branch_escape)
      assert template_repo.update_default_branch("zzz"),
        "need a default branch in the template repo that differs from the clone's default branch"
      new_repo = create(:repository)

      Repository.any_instance.stubs(:branch_being_renamed?).returns(true)

      orchestration = RepositoryOrchestration.clone_template(template_repository: template_repo, actor: new_repo.owner, new_repository: new_repo)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        orchestration.execute
      end

      assert_equal "failed", orchestration.reload.state
      assert_equal "error", orchestration.repo_clone.reload.state
      assert_equal "failed_to_update_branch", orchestration.repo_clone.error_reason_code
    end

    test "sets default branch of new repo to match template repo" do
      template_repo = create(:repository, template: true, from_example: :branch_escape)
      default_branch = "zzz"
      assert template_repo.update_default_branch(default_branch),
        "need a default branch in the template repo that differs from the clone's default branch"
      new_repo = create(:repository)

      orchestration = RepositoryOrchestration.clone_template(template_repository: template_repo, actor: new_repo.owner, new_repository: new_repo)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        orchestration.execute
      end

      assert orchestration.reload.succeeded?
      assert_equal "finished", orchestration.repo_clone.reload.state
      assert_equal default_branch, new_repo.reload.default_branch,
        "should have set new repo's default branch to match template's"
      assert_initial_commit orchestration.repo_clone
      assert_same_files template_repo, new_repo
    end

    test "does not fail if default branch is already correctly set by push job" do
      template_repo = create(:repository, template: true, from_example: :branch_escape)
      default_branch = "zzz"
      assert template_repo.update_default_branch(default_branch),
        "need a default branch in the template repo that differs from the clone's default branch"
      new_repo = create(:repository)

      orchestration = RepositoryOrchestration.clone_template(template_repository: template_repo, actor: new_repo.owner, new_repository: new_repo)

      # Construct a situation where the default branch is changed by the push job before the
      CloneTemplateOrchestration.stop_after_step = :copy_branches
      # Might need the HydroRepositoriesOnPushJob too
      perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
        orchestration.execute(synchronous: true)
      end
      # And require that the attempt to update the default branch fails
      new_repo.stubs(:update_default_branch).returns(false)
      # Orchestration should still succeed since the default branch was already updated by the push job
      orchestration.execute(synchronous: true)

      assert orchestration.reload.succeeded?
      assert_equal "finished", orchestration.repo_clone.reload.state
      assert_equal default_branch, new_repo.reload.default_branch,
        "should have set new repo's default branch to match template's"
      assert_initial_commit orchestration.repo_clone
      assert_same_files template_repo, new_repo
    end

    test "errors if there is a git error" do
      template = create(:repository, template: true, from_example: :invalid_objects_test)
      base_ref = template.heads.build(template.default_branch)
      cloning_user = create(:user)
      new_repo = create(:repository, owner: cloning_user)

      orchestration = RepositoryOrchestration.clone_template(template_repository: template, actor: cloning_user, new_repository: new_repo)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        assert_nothing_raised do
          orchestration.execute
        end
      end

      assert orchestration.reload.failed?
      assert_equal "error", orchestration.repo_clone.reload.state
      assert_equal "no_commit_oid", orchestration.repo_clone.error_reason_code
    end

    test "copies repos smaller than than the max size" do
      template = create(:repository, template: true, from_example: :repository_test_simple)

      cloning_user = create(:user)
      new_repo = create(:repository, owner: cloning_user)

      Repository.any_instance.stubs(:disk_usage).returns(900_000.kilobytes)

      orchestration = RepositoryOrchestration.clone_template(template_repository: template, actor: cloning_user, new_repository: new_repo)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        orchestration.execute
      end

      assert orchestration.reload.succeeded?
      assert_equal "finished", orchestration.repo_clone.reload.state
      assert_initial_commit orchestration.repo_clone
      assert_same_files template, new_repo
    end

    test "errors if repository disk usage is more than max size" do
      template = create(:repository, template: true, from_example: :repository_test_simple)

      cloning_user = create(:user)
      new_repo = create(:repository, owner: cloning_user)

      Repository.any_instance.stubs(:disk_usage).returns(1_100_000.kilobytes)

      orchestration = RepositoryOrchestration.clone_template(template_repository: template, actor: cloning_user, new_repository: new_repo)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        assert_nothing_raised do
          orchestration.execute
        end
      end

      assert orchestration.reload.failed?
      assert_equal "error", orchestration.repo_clone.reload.state
      assert_equal "repo_size_too_large", orchestration.repo_clone.error_reason_code
    end

    test "errors if the repository contains more than 100,000 files" do
      template = create(:repository, template: true, from_example: :empty)
      base_ref = template.heads.build(template.default_branch)
      base_ref.append_commit({ message: "Add large file",
                              committer: template.owner }, template.owner)
      cloning_user = create(:user)
      new_repo = create(:repository, owner: cloning_user)

      # Rather than create a repository with 100,000 files, we can stub `tree_entries`
      # to return a truncated result set, which indicates that the repo contains
      # more than the max number of allowed files.
      Repository.any_instance.stubs(:tree_entries).returns([nil, nil, true])

      orchestration = RepositoryOrchestration.clone_template(template_repository: template, actor: cloning_user, new_repository: new_repo)

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        assert_nothing_raised do
          orchestration.execute
        end
      end

      assert orchestration.reload.failed?
      assert_equal "error", orchestration.repo_clone.reload.state
      assert_equal "other_exception", orchestration.repo_clone.error_reason_code
      assert_equal "copy branch failed: too many files for template repo branch", orchestration.error_message
    end

    test "creates Push record" do
      template_repo = create(:repository, template: true, from_example: :simple)
      new_repo = create(:repository)

      assert_equal 0, Push.annotate("cross-shard-query-exempted").all.count

      orchestration = RepositoryOrchestration.clone_template(template_repository: template_repo, actor: new_repo.owner, new_repository: new_repo)

      perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
        perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          orchestration.execute
        end
      end

      assert orchestration.reload.succeeded?
      oid = new_repo.default_oid
      default_branch = new_repo.reload.default_branch

      assert_equal 1, Push.annotate("cross-shard-query-exempted").where(ref: "refs/heads/#{default_branch}", after: oid).count
    end

    test "skips when repository is deleted" do
      repo_1 = create(:repository, owner: @owner)
      repo_2 = create(:repository, owner: @owner)
      o_1 = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: @owner, new_repository: repo_1)
      o_2 = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: @owner, new_repository: repo_2)

      o_1.execute # run o_1's sync steps first before stubbing deleted, so we can test that it skips from the async portion
      Repository.any_instance.stubs(:deleted?).returns(true)
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      o_2.execute

      assert o_1.reload.skipped?
      assert o_2.reload.skipped?
    end

    test "skips when create orchestration skips" do
      CreateRepositoryOrchestration.any_instance.stubs(:skipped?).returns(true)
      orchestration = RepositoryOrchestration.clone_template(template_repository: @template_repo, actor: @owner, owner: @owner,
                                           name: @name, visibility: "public",
                                           description: @description)

      orchestration.execute
      refute orchestration.succeeded?
      assert orchestration.skipped?

      assert_equal "create orchestration ID: #{orchestration.create_orchestration.id} skipped", orchestration.error_message
    end
  end

  def assert_initial_commit(repo_clone)
    new_repo = repo_clone.clone_repository
    assert_commit_in_branch(new_repo.default_branch, repo: new_repo, user: repo_clone.cloning_user)

    commit_oid = new_repo.ref_to_sha(new_repo.default_branch)
    commit = new_repo.commits.paged_history(commit_oid).first
    assert_equal "Initial commit", commit.message,
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

    commit_oid = new_repo.ref_to_sha(branch_name)
    refute_nil commit_oid, "new repo should have a commit in branch '#{branch_name}'"
    actual_files = new_repo.tree_file_list(commit_oid, skip_directories: [])

    assert_equal expected_files, actual_files,
      "expected new repository to have the same files as the template repo in branch '#{branch_name}'"

    expected_files.each do |expected_path|
      expected_tree_entry = template_repo.tree_entry(tmpl_commit_oid, expected_path)
      actual_tree_entry = new_repo.tree_entry(commit_oid, expected_path)
      assert_equal expected_tree_entry.data, actual_tree_entry.data,
        "new repo should have same file contents as template in #{expected_path} in branch '#{branch_name}'"
      if expected_tree_entry.encoding
        assert_equal expected_tree_entry.encoding, actual_tree_entry.encoding,
          "new repo should have same file encoding as template for #{expected_path} in branch '#{branch_name}'"
      else
        assert_nil actual_tree_entry.encoding,
          "new repo should lack file encoding like template does for #{expected_path} in branch '#{branch_name}'"
      end
    end
  end
end
