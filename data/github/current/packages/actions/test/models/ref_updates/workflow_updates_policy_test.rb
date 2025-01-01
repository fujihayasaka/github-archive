# typed: false
# frozen_string_literal: true

require "test_helper"

class RefUpdates::WorkflowUpdatePolicyTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers

  fixtures do
    @user = create(:user)
    @oauth_user = create(:user)
    @repo = create(:repository, owner: @user)

    @owner = create :paid_user, login: "octocat"
    @org = create :organization, admin: @owner, login: "github"
    @app = create :integration, default_permissions: { "checks" => :write }, owner: @org
    @app_with_workflow_permission = create :integration, default_permissions: { "workflows" => :write }, owner: @org
    @installation = make_integration_installation(integration: @app, repository: @repo)
    @installation_with_workflow_permission = make_integration_installation(integration: @app_with_workflow_permission, repository: @repo)

    @business = create :business, owners: [@owner]
    @enterprise_org = create :organization, admin: @owner, business: @business
    @enterprise_repo = create :repository, owner: @enterprise_org

    @enterprise_app = create :enterprise_owned_integration, default_permissions: { "checks" => :write }, owner: @business
    @enterprise_app_with_workflow_permission = create :enterprise_owned_integration, default_permissions: { "workflows" => :write }, owner: @business

    @enterprise_installation = make_integration_installation(integration: @enterprise_app, repository: @enterprise_repo)
    @enterprise_installation_with_workflow_permission = make_integration_installation(integration: @enterprise_app_with_workflow_permission, repository: @enterprise_repo)

    # Create a global app with static installation permissions and an
    # installation on the repository. This mimics how Codespaces works with
    # extended repository permissions.
    @global_app = create_privileged_app_with_capabilities(
      capabilities: {
        installed_globally: true,
        static_installation_repository_permissions: true,
        limited_access: false,
      },
      properties: {
        static_installation_repository_permissions: { "metadata" => :read },
      },
      permissions: {
        "metadata" => :read,
        "workflows" => :write,
      },
      options: { name: "Global App" },
    )
    disable_feature_flag(:disabled_global_apps, @global_app)
    make_integration_installation(integration: @global_app, repository: @repo)
    enable_feature_flag(:launch_lab, @repo)
    enable_feature_flag(:launch_lab, @enterprise_repo)
  end

  setup do
    @repo.refs.map do |ref|
      ref.delete(@owner)
    end

    @enterprise_repo.refs.map do |ref|
      ref.delete(@owner)
    end
  end

  def user_for_test_type(test_type)
    case test_type
    when :human
      @user
    when :app_bot
      @installation.bot
    when :enterprise_app_bot
      @enterprise_installation.bot
    when :pat
      @user.oauth_access = make_personal_access_token(@user, "repo")
      @user
    when :pat_with_workflow_scope
      @user.oauth_access = make_personal_access_token(@user, %w[repo workflow])
      @user
    when :oauth_user
      configure_user_as_oauth_app(@oauth_user, ["repo"])
    when :app_user
      @user.oauth_access = @app.grant(@user)
      @user
    when :enterprise_app_user
      @owner.oauth_access = @enterprise_app.grant(@owner)
      @owner
    when :app_bot_with_workflow_permission
      @installation_with_workflow_permission.bot
    when :enterprise_app_bot_with_workflow_permission
      @enterprise_installation_with_workflow_permission.bot
    when :oauth_user_with_workflow_write
      configure_user_as_oauth_app(@oauth_user, %w[repo workflow])
    when :app_user_with_workflow_permission
      @user.oauth_access = @app_with_workflow_permission.grant(@user)
      @user
    when :enterprise_app_user_with_workflow_permission
      @owner.oauth_access = @enterprise_app_with_workflow_permission.grant(@owner)
      @owner
    when :scoped_global_app_user
      access = @global_app.grant(@user)
      @global_app.grant_repository_scoped_installation_on(access, repository_id: @repo.id)
      @user.oauth_access = access
      @user
    when :programmatic_access_bot
      access = create(:user_programmatic_access, owner: @user)
      grant = make_programmatic_access_grant(
        access: access, requester: @user, repository_selection: :all,
        permissions: { "metadata" => :read }
      ).bot
    when :programmatic_access_bot_with_workflow_scope
      access = create(:user_programmatic_access, owner: @user)
      grant = make_programmatic_access_grant(
        access: access, requester: @user, repository_selection: :all,
        permissions: { "metadata" => :read, "workflows" => :write }
      ).bot
    end
  end

  def repo_for_test_type(test_type)
    case test_type
    when :enterprise_app_bot,
         :enterprise_app_bot_with_workflow_permission,
         :enterprise_app_user,
         :enterprise_app_user_with_workflow_permission
      @enterprise_repo
    else
      @repo
    end
  end

  AUTH_TYPES = %i(
    human app_bot app_bot_with_workflow_permission oauth_user pat pat_with_workflow_scope app_user
    oauth_user_with_workflow_write app_user_with_workflow_permission scoped_global_app_user
    programmatic_access_bot programmatic_access_bot_with_workflow_scope
    enterprise_app_bot enterprise_app_bot_with_workflow_permission enterprise_app_user enterprise_app_user_with_workflow_permission
  )

  AUTH_TYPES.each do |test_type|
    test "#{test_type} pushing normal files" do
      repo = repo_for_test_type(test_type)
      oid_update_readme = create_commit(repo, nil, "update README", {
        "README" => "lorem ipsum\n",
      })
      ref_updates = [Git::Ref::Update.new(
        repository: repo,
        before_oid: GitHub::NULL_OID,
        refname: "refs/heads/master",
        after_oid: oid_update_readme,
      )]
      decisions = RefUpdatesPolicy.check(repo, ref_updates, user_for_test_type(test_type))

      assert_predicate decisions[0], :allowed?
    end
  end

  ref_updates = {
    [:human, "README"] =>                                       :success,
    [:app_bot, "README"] =>                                     :success,
    [:app_bot_with_workflow_permission, "README"] =>            :success,
    [:enterprise_app_bot, "README"] =>                          :success,
    [:enterprise_app_bot_with_workflow_permission, "README"] => :success,
    [:pat, "REAME"] =>                                          :success,
    [:pat_with_workflow_scope, "REAME"] =>                      :success,
    [:oauth_user, "README"] =>                                  :success,
    [:app_user, "README"] =>                                    :success,
    [:oauth_user_with_workflow_write, "README"] =>              :success,
    [:app_user_with_workflow_permission, "README"] =>           :success,
    [:scoped_global_app_user, "README"] =>                      :success,
    [:programmatic_access_bot, "README"] =>                     :success,
    [:programmatic_access_bot_with_workflow_scope, "README"] => :success,

    [:human, ".github/workflows/a.yml"] =>                                       :success,
    [:app_bot, ".github/workflows/a.yml"] =>                                     :failure,
    [:enterprise_app_bot, ".github/workflows/a.yml"] =>                          :failure,
    [:pat, ".github/workflows/a.yml"] =>                                         :failure,
    [:pat_with_workflow_scope, ".github/workflows/a.yml"] =>                     :success,
    [:oauth_user, ".github/workflows/a.yml"] =>                                  :failure,
    [:app_user, ".github/workflows/a.yml"] =>                                    :failure,
    [:app_bot_with_workflow_permission, ".github/workflows/a.yml"] =>            :success,
    [:enterprise_app_bot_with_workflow_permission, ".github/workflows/a.yml"] => :success,
    [:oauth_user_with_workflow_write, ".github/workflows/a.yml"] =>              :success,
    [:app_user_with_workflow_permission, ".github/workflows/a.yml"] =>           :success,
    [:scoped_global_app_user, ".github/workflows/a.yml"] =>                      :success,
    [:programmatic_access_bot, ".github/workflows/a.yml"] =>                     :failure,
    [:programmatic_access_bot_with_workflow_scope, ".github/workflows/a.yml"] => :success,

    [:human, ".github/workflows-lab/b.yaml"] =>                                      :success,
    [:app_bot, ".github/workflows-lab/b.yaml"] =>                                    :failure,
    [:enterprise_app_bot, ".github/workflows-lab/b.yaml"] =>                         :failure,
    [:pat, ".github/workflows-lab/b.yaml"] =>                                        :failure,
    [:pat_with_workflow_scope, ".github/workflows-lab/b.yaml"] =>                    :success,
    [:oauth_user, ".github/workflows-lab/b.yaml"] =>                                 :failure,
    [:app_user, ".github/workflows-lab/b.yaml"] =>                                   :failure,
    [:app_bot_with_workflow_permission, ".github/workflows-lab/b.yaml"] =>           :success,
    [:enterprise_app_bot_with_workflow_permission, ".github/workflows-lab/b.yaml"] => :success,
    [:oauth_user_with_workflow_write, ".github/workflows-lab/b.yaml"] =>             :success,
    [:app_user_with_workflow_permission, ".github/workflows-lab/b.yaml"] =>          :success,
    [:scoped_global_app_user, ".github/workflows-lab/b.yml"] =>                      :success,
    [:programmatic_access_bot, ".github/workflows-lab/b.yml"] =>                     :failure,
    [:programmatic_access_bot_with_workflow_scope, ".github/workflows-lab/b.yml"] => :success,
  }
  ref_updates.each do |(test_type, file), expected_result|
    test "#{test_type} pushing #{file} commit objects" do
      repo = repo_for_test_type(test_type)
      oid_add_workflow = create_commit(repo, nil, "add #{file}", {
        file => "# foo\n",
      })
      oid_update_workflow = create_commit(repo, oid_add_workflow, "update #{file}", {
        file => "# foo\n# bar\n",
      })
      oid_delete_workflow = create_commit(repo, oid_update_workflow, "delete #{file}", {
        file => nil,
      })
      ref_updates = [
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/tags/commit-add",
          before_oid: GitHub::NULL_OID,
          after_oid: oid_add_workflow,
        ),
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/tags/commit-update",
          before_oid: oid_add_workflow,
          after_oid: oid_update_workflow,
        ),
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/tags/commit-delete",
          before_oid: oid_add_workflow,
          after_oid: oid_delete_workflow,
        ),
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/tags/remove-commit-delete",
          before_oid: oid_add_workflow,
          after_oid: GitHub::NULL_OID,
        ),
      ]
      decisions = ref_updates.map do |ref_update|
        RefUpdates::WorkflowUpdatesPolicy.new(user_for_test_type(test_type), repo).check_ref_update(ref_update.before_oid, ref_update.after_oid)
      end

      if expected_result == :success
        assert_predicate decisions[0], :allowed?
        assert_predicate decisions[1], :allowed?
        assert_predicate decisions[2], :allowed?
        assert_predicate decisions[3], :allowed?
      else
        refute_predicate decisions[0], :allowed?
        assert_equal bot_action_prohibited_message(test_type, file), decisions[0].short_message
        assert_nil decisions[0].long_message

        refute_predicate decisions[1], :allowed?
        assert_equal bot_action_prohibited_message(test_type, file), decisions[1].short_message
        assert_nil decisions[1].long_message

        assert_predicate decisions[2], :allowed?
        assert_predicate decisions[3], :allowed?
      end
    end

    test "#{test_type} pushing #{file} tag objects" do
      repo = repo_for_test_type(test_type)
      oid_add_workflow = create_commit(repo, nil, "add #{file}", {
        file => "# foo\n",
      })
      oid_tag = create_tag_annotation(repo, "test-tag", oid_add_workflow)
      ref_updates = [
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/tags/add-tag",
          before_oid: GitHub::NULL_OID,
          after_oid: oid_tag,
        ),
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/tags/delete-tag",
          before_oid: oid_tag,
          after_oid: GitHub::NULL_OID,
        ),
      ]
      decisions = ref_updates.map do |ref_update|
        RefUpdates::WorkflowUpdatesPolicy.new(user_for_test_type(test_type), repo).check_ref_update(ref_update.before_oid, ref_update.after_oid)
      end

      if expected_result == :success
        assert_predicate decisions[0], :allowed?
        assert_predicate decisions[1], :allowed?
      else
        refute_predicate decisions[0], :allowed?
        assert_equal bot_action_prohibited_message(test_type, file), decisions[0].short_message
        assert_nil decisions[0].long_message

        assert_predicate decisions[1], :allowed?
      end
    end

    test "#{test_type} pushing #{file} blob objects" do
      repo = repo_for_test_type(test_type)
      blob1_oid = create_blob(repo, "blob1")
      blob2_oid = create_blob(repo, "blob2")
      ref_updates = [
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/tags/add-blob",
          before_oid: GitHub::NULL_OID,
          after_oid: blob1_oid,
        ),
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/tags/update-blob",
          before_oid: blob1_oid,
          after_oid: blob2_oid,
        ),
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/tags/delete-blob",
          before_oid: blob2_oid,
          after_oid: GitHub::NULL_OID,
        ),
      ]
      decisions = ref_updates.map do |ref_update|
        RefUpdates::WorkflowUpdatesPolicy.new(user_for_test_type(test_type), repo).check_ref_update(ref_update.before_oid, ref_update.after_oid)
      end
      assert_predicate decisions[0], :allowed?
      assert_predicate decisions[1], :allowed?
      assert_predicate decisions[2], :allowed?
    end

    test "#{test_type} pushing #{file} tree objects" do
      repo = repo_for_test_type(test_type)
      commit1_oid = create_commit(repo, nil, "add #{file}", {
        file => "# foo\n",
      })
      tree1_oid = get_tree(repo, commit1_oid, ".")
      commit2_oid = create_commit(repo, nil, "add #{file}", {
        file => "# bar\n",
      })
      tree2_oid = get_tree(repo, commit2_oid, ".")
      ref_updates = [
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/tags/tree-add",
          before_oid: GitHub::NULL_OID,
          after_oid: tree1_oid,
        ),
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/tags/tree-update",
          before_oid: tree1_oid,
          after_oid: tree2_oid,
        ),
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/tags/tree-commit",
          before_oid: commit1_oid,
          after_oid: tree2_oid,
        ),
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/tags/tree-delete",
          before_oid: tree2_oid,
          after_oid: GitHub::NULL_OID,
        ),
      ]
      decisions = ref_updates.map do |ref_update|
        RefUpdates::WorkflowUpdatesPolicy.new(user_for_test_type(test_type), repo).check_ref_update(ref_update.before_oid, ref_update.after_oid)
      end
      if expected_result == :success
        assert_predicate decisions[0], :allowed?
        assert_predicate decisions[1], :allowed?
        assert_predicate decisions[2], :allowed?
        assert_predicate decisions[3], :allowed?
      else
        refute_predicate decisions[0], :allowed?
        refute_predicate decisions[1], :allowed?
        refute_predicate decisions[2], :allowed?
        assert_predicate decisions[3], :allowed?
      end
    end

    test "#{test_type} pushing #{file} commit replacing non-commit" do
      repo = repo_for_test_type(test_type)
      blob_oid = create_blob(repo, "blob1")
      commit_add_workflow = create_commit(repo, nil, "add #{file}", {
        file => "# foo\n",
      })
      commit_delete_workflow = create_commit(repo, commit_add_workflow, "delete #{file}", {
        file => nil,
      })
      ref_updates = [
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/tags/blob-commit-add",
          before_oid: blob_oid,
          after_oid: commit_add_workflow,
        ),
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/tags/blob-commit-delete",
          before_oid: blob_oid,
          after_oid: commit_delete_workflow,
        ),
      ]
      decisions = ref_updates.map do |ref_update|
        RefUpdates::WorkflowUpdatesPolicy.new(user_for_test_type(test_type), repo).check_ref_update(ref_update.before_oid, ref_update.after_oid)
      end
      if expected_result == :success
        assert_predicate decisions[0], :allowed?
        assert_predicate decisions[1], :allowed?
      else
        refute_predicate decisions[0], :allowed?
        assert_predicate decisions[1], :allowed?
      end
    end

    test "#{test_type} pushing #{file} commit which exists on another ref" do
      repo = repo_for_test_type(test_type)
      oid_add_workflow = create_commit(repo, nil, "add #{file}", {
        file => "# foo\n",
      })
      oid_update_workflow = create_commit(repo, oid_add_workflow, "update #{file}", {
        file => "# foo\n# bar\n",
      })
      repo.batch_write_refs(@owner, [
        ["refs/heads/e1", nil, oid_add_workflow],
        ["refs/heads/t2", nil, oid_update_workflow],
      ])
      ref_updates = [
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/heads/commit-on-ref1",
          before_oid: GitHub::NULL_OID,
          after_oid: oid_add_workflow,
        ),
        Git::Ref::Update.new(
          repository: repo,
          refname: "refs/heads/commit-on-ref2",
          before_oid: oid_add_workflow,
          after_oid: oid_update_workflow,
        ),
      ]
      decisions = RefUpdatesPolicy.check(repo, ref_updates, user_for_test_type(test_type))
      assert_predicate decisions[0], :allowed?
      assert_predicate decisions[1], :allowed?
    end
  end

  test "pushing two workflow files which exist on one branch but not on another" do
    repo = repo_for_test_type(:pat)
    oid_add_workflow_files = create_commit(repo, nil, "add workflow a", {
      ".github/workflows/a.yml" => "a",
      ".github/workflows/b.yml" => "b",
    })
    oid_add_readme = create_commit(repo, nil, "add readme", "README.md" => "a")
    repo.batch_write_refs(@owner, [
      ["refs/heads/a", nil, oid_add_workflow_files],
      ["refs/heads/b", nil, oid_add_readme],
    ])

    ref_updates = [
      Git::Ref::Update.new(
        repository: repo,
        refname: "refs/heads/c",
        before_oid: GitHub::NULL_OID,
        after_oid: oid_add_workflow_files,
      ),
    ]
    decisions = RefUpdatesPolicy.check(repo, ref_updates, user_for_test_type(:pat))
    assert_predicate decisions[0], :allowed?
  end

  test "handle refs that do not exist for some reason." do
    repo = repo_for_test_type(:pat)
    mysteriously_missing_oid = "a" * 40 # not a real oid (probably)

    workflow_filename = ".github/workflows/a.yml"
    oid_dangerous_commit = create_commit(repo, nil, "create #{workflow_filename}", {
      workflow_filename => "# foo\n# bar\n",
    })

    ref_updates = [
      # create missing ref
      Git::Ref::Update.new(
        repository: repo,
        refname: "refs/heads/ohno0",
        before_oid: GitHub::NULL_OID,
        after_oid: mysteriously_missing_oid,
      ),
      # delete missing ref
      Git::Ref::Update.new(
        repository: repo,
        refname: "refs/heads/ohno1",
        before_oid: mysteriously_missing_oid,
        after_oid: GitHub::NULL_OID,
      ),
      # implicit delete workflow
      Git::Ref::Update.new(
        repository: repo,
        refname: "refs/heads/ohno2",
        before_oid: oid_dangerous_commit,
        after_oid: mysteriously_missing_oid,
      ),
      # implicit create workflow
      Git::Ref::Update.new(
        repository: repo,
        refname: "refs/heads/ohno3",
        before_oid: mysteriously_missing_oid,
        after_oid: oid_dangerous_commit,
      ),
    ]
    decisions = RefUpdatesPolicy.check(repo, ref_updates, user_for_test_type(:pat))
    assert_predicate decisions[0], :allowed?
    assert_predicate decisions[1], :allowed?
    # refute_predicate decisions[2], :allowed? # TODO: this case should probably not be allowed. https://github.com/github/github/pull/213737
    refute_predicate decisions[3], :allowed?
  end

  test "GitRPC::Timeout custom error occurs when the RPC times out in the 'check_files_update' on the non-default branch" do
    file = RefUpdates::WorkflowUpdatesPolicy::FileUpdate.new(".github/workflows/a.yml", "a")
    ref_updates = RefUpdates::WorkflowUpdatesPolicy.new(user_for_test_type(:pat), repo_for_test_type(:pat))

    # stubs
    first_args = [[file], [], equals(timeout: 1)]
    second_args = [[file], [], equals(timeout: 3)]
    ref_updates.stubs(:files_missing_from_branches).with(*first_args).returns([file])
    ref_updates.stubs(:files_missing_from_branches).with(*second_args).raises(GitRPC::Timeout)

    err = assert_raises(GitRPC::Timeout) { ref_updates.check_files_update([file]) }
    assert_equal("Timed out while checking if workflow scope is required - all branches check", err.message)
  end

  test "GitRPC::Timeout custom error occurs when the RPC times out in the 'check_file_update' on the non-default branch" do
    file = RefUpdates::WorkflowUpdatesPolicy::FileUpdate.new(".github/workflows/a.yml", "a")
    ref_updates = RefUpdates::WorkflowUpdatesPolicy.new(user_for_test_type(:pat), repo_for_test_type(:pat))

    # stubs
    first_args = [[file], [], equals(timeout: 1)]
    second_args = [[file], [], equals(timeout: 3)]
    ref_updates.stubs(:files_missing_from_branches).with(*first_args).returns([file])
    ref_updates.stubs(:files_missing_from_branches).with(*second_args).raises(GitRPC::Timeout)
    RefUpdates::WorkflowUpdatesPolicy::FileUpdate.stubs(:new).with(".github/workflows/a.yml", "a").returns(file)

    err = assert_raises(GitRPC::Timeout) { ref_updates.check_file_update(".github/workflows/a.yml", "a") }
    assert_equal("Timed out while checking if workflow scope is required - all branches check", err.message)
  end

  test "GitRPC::Timeout custom error occurs when the RPC times out in the 'check_files_update' on the default branch" do
    file = RefUpdates::WorkflowUpdatesPolicy::FileUpdate.new(".github/workflows/a.yml", "a")
    ref_updates = RefUpdates::WorkflowUpdatesPolicy.new(user_for_test_type(:pat), repo_for_test_type(:pat))

    # stubs
    first_args = [[file], [], equals(timeout: 1)]
    ref_updates.stubs(:files_missing_from_branches).with(*first_args).raises(GitRPC::Timeout)

    err = assert_raises(GitRPC::Timeout) { ref_updates.check_files_update([file]) }
    assert_equal("Timed out while checking if workflow scope is required - default branch check", err.message)
  end

  test "GitRPC::Timeout custom error occurs when the RPC times out in the 'check_file_update' on the default branch" do
    file = RefUpdates::WorkflowUpdatesPolicy::FileUpdate.new(".github/workflows/a.yml", "a")
    ref_updates = RefUpdates::WorkflowUpdatesPolicy.new(user_for_test_type(:pat), repo_for_test_type(:pat))

    # stubs
    first_args = [[file], [], equals(timeout: 1)]
    ref_updates.stubs(:files_missing_from_branches).with(*first_args).raises(GitRPC::Timeout)
    RefUpdates::WorkflowUpdatesPolicy::FileUpdate.stubs(:new).with(".github/workflows/a.yml", "a").returns(file)

    err = assert_raises(GitRPC::Timeout) { ref_updates.check_file_update(".github/workflows/a.yml", "a") }
    assert_equal("Timed out while checking if workflow scope is required - default branch check", err.message)
  end

  def create_commit(repo, parent, message, files)
    repo.rpc.create_tree_changes(parent, {
      "message"   => message,
      "committer" => {
        "email"   => @user.git_author_email,
        "name"    => @user.git_author_name,
        "time"    => @user.time_zone.now.iso8601,
      },
    }, files)
  end

  def create_tag_annotation(repo, tag_name, target_oid)
    repo.spokes_api.with_transaction do
      repo.spokes_api.create_tag(name: tag_name, target: target_oid,
        message: "test tag",
        tagger: {
          name: "Hayden Faulds",
          email: "hfaulds@github.com",
          time: Time.now,
        }
      )
    end
  end

  def create_blob(repo, content)
    repo.rpc.write_blob(content)
  end

  def get_tree(repo, commit_oid, path)
    repo.rpc.read_tree_entry(commit_oid, path).fetch("oid")
  end

  def bot_action_prohibited_message(test_type, file)
    if test_type == :pat
      "refusing to allow a Personal Access Token to create or update workflow `#{file}` without `workflow` scope"
    elsif test_type == :oauth_user || test_type == :oauth_user_with_workflow_write
      "refusing to allow an OAuth App to create or update workflow `#{file}` without `workflow` scope"
    else
      "refusing to allow a GitHub App to create or update workflow `#{file}` without `workflows` permission"
    end
  end
end
