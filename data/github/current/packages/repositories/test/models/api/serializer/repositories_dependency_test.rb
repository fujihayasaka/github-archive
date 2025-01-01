# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class RepoSerializersTest < Api::SerializerTestCase
  include PageHelper
  include AvatarHelper

  fixtures do
    @owner = create :paid_user, login: "owner"

    @org_admin = create :user, plan: "medium"
    @org   = create :organization, admin: @org_admin, plan: GitHub::Plan.business

    @rando = create(:user)

    @repo = create :repository, owner: @owner, name: "Kunze-Smith", has_discussions: true, from_example: :simple

    @repo_clone = create :repository_clone, clone_repository: @repo

    @priv_repo = create :private_repository, owner: @owner, from_example: :simple

    @disabled_repo = create :repository, owner: @owner
    staff = create(:staff_admin_user)
    @disabled_repo.access.disable("size", staff)

    @submodule_repo = create(:repository, name: "tree_with_submod", owner: @owner, from_example: :tree_with_submod)

    @org_repo = create :repository, owner: @org

    @tree_object = TreeEntry.new(@repo, {
      "type" => "tree",
      "oid"  => @repo.heads["master"].commit.tree_oid,
      "path" => "",
    }).freeze

    @internal_repo = create :internal_repository
    biz = @internal_repo.owner.business
    @biz_owner = biz.owners.first
    @other_biz_org = create :enterprise_linked_organization, business: biz
    @other_biz_user = create :user
    @other_biz_org.add_member(@other_biz_user, adder: @other_biz_org.admins.first)

    @forked_repo, _reason, _errors = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @repo.fork(forker: @rando) }

    @invitation = create(:repository_invitation,
      invitee: @rando,
      inviter: @owner,
      repository: @priv_repo,
      permissions: 1,
    )

    @inline_comment = create :commit_comment, repository: @repo, commit_id: @repo.default_oid, user: @owner
    @commit_comment = create :commit_comment, repository: @repo, commit_id: @repo.default_oid, user: @owner, path: nil, position: nil
    @page = create :page, owner: @owner
    @build = Page::Build.create! page: @page, pusher_id: @owner.id, status: "built", commit: "abc"

    # we have a test that needs to validate that the client can change the global id
    # headers, so we need to ensure the repository owner for this test was created before the cutover date
    # for the `User` object in GraphQL - 2021-09-28
    #
    # This Timecop call can be removed when the global id migration is completed and we do not need to support global_id_selection
    date_before_user_next_global_id = Time.new(2020, 8, 17, 0, 8, 0).utc
    Timecop.freeze(date_before_user_next_global_id) do
      @repo_for_release_testing = create(:repository, from_example: :tags_galore)
      @release_with_asset = create(:release,
        name: "v1.0",
        tag_name: "v1.0",
        author: @repo_for_release_testing.owner,
        repository: @repo_for_release_testing,
        target_commitish: "master",
        body: "thanks @#{@repo_for_release_testing.owner}",
      )

      @release_asset = create(:release_asset, uploader: @repo_for_release_testing.owner, release: @release_with_asset, name: "fake.zip")

      user_to_destroy = create(:user)
      @repo_for_release_testing.add_member(user_to_destroy)
      @release_asset_without_uploader = create(:release_asset, uploader: user_to_destroy, release: @release_with_asset, name: "orphaned.zip")
    end
  end

  context "#commit_comment_hash" do
    test "payload is valid" do
      output = commit_comment(@commit_comment)
      assert output.key?("url")
      assert output.key?("html_url")
      assert output.key?("id")
      assert output.key?("node_id")
    end

    test "when comment is on the diff, the html_url has a `r#id` fragment" do
      output = commit_comment(@inline_comment)
      assert output["html_url"].end_with? "r#{@inline_comment.id}"
    end

    test "returns nil if no comment is provided" do
      assert_nil commit_comment(nil)
    end

    test "when reactions preview is passed, the reactions key is present" do
      output = commit_comment(@commit_comment)

      assert output["reactions"]
    end
  end

  context "#short_branch_with_protection_hash" do
    test "payload is valid" do
      ref = @repo.refs["master"]
      output = short_branch_with_protection(ref)
      assert_same_elements %w[name commit protected protection protection_url], output.keys
    end
  end

  context "#full_repository_hash" do
    test "payload is valid" do
      output = full_repository(@repo)
      assert output.key?("id")
      assert output.key?("node_id")
      assert output.key?("name")
      assert output.key?("full_name")
    end

    test "returns nil if repo is nil" do
      assert_nil full_repository(nil)
    end

    test "returns organization key when repo is owned by an org" do
      output = full_repository(@org_repo)

      assert output["organization"]
    end

    test "does not return parent and source key when repo is not a fork" do
      output = full_repository(@repo)

      refute output["parent"]
      refute output["source"]
    end

    test "returns parent key and source key when repo is a fork" do
      output = full_repository(@forked_repo)

      assert output["parent"]
      assert output["source"]
    end

    test "the template_repository key is present" do
      options = {
        show_template_repository: true
      }
      output = full_repository(@repo, options)

      assert output.key?("template_repository")
    end

    test "when org default branch is trunk, the repo hash uses trunk as the fallback value if repo not yet online" do
      Organization.any_instance.stubs(:custom_default_new_repo_branch).returns("trunk")
      repo = create :repository, owner: @org, created_by_user_id: @org_admin.id
      # Here we stub `default_branch` to throw an exception to reproduce the way the serializer will behave
      # when we are serializing this repo just after its creation. The repo won't be online yet so we need to
      # infer its default branch by checking the owner's default branch preference.
      # This ensures that webhooks that happen on repo creation will have the proper value.
      Repository.any_instance.stubs(:default_branch).raises(GitRPC::RepositoryOffline.new("host", "path"))
      payload = full_repository(repo)
      assert_equal "trunk", payload["default_branch"]
    end

    test "for repositories created from a template, the repo hash uses the template's default branch as fallback value if repo not yet online" do
      template_repo = create(:repository, template: true, owner: @owner, from_example: :simple)
      renamer = RepositoryBranchRenamer.for_starting_rename_process(branch_name: template_repo.default_branch, repository: template_repo)
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        renamer.start_rename("trunk", actor: @owner, entry_point: :test_case)
      end
      repo = create(:repository, owner: @owner)
      create(:repository_clone, template_repository: template_repo, clone_repository: repo)
      repo.stubs(:default_branch).raises(GitRPC::RepositoryOffline.new("host", "path"))
      payload = full_repository(repo)
      assert_equal "trunk", payload["default_branch"]
    end

    test "for forks, default_branch is the fork's own default branch, not its parent's" do
      repo_fork = create(:fork_repository, forker: @rando, fork_repo: @repo, from_example: :simple)
      renamer = RepositoryBranchRenamer.for_starting_rename_process(branch_name: repo_fork.default_branch, repository: repo_fork)
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        assert renamer.start_rename("develop", actor: @owner, entry_point: :test_case)
      end
      payload = full_repository(repo_fork.reload)
      assert_equal "develop", payload["default_branch"]
    end

    test "for repos made from templates, default_branch is the repo's own, not the template's" do
      template_repo = create(:repository, template: true, owner: @owner, from_example: :simple)
      repo = create(:repository, owner: @owner, from_example: :simple)
      create(:repository_clone, template_repository: template_repo, clone_repository: repo)
      renamer = RepositoryBranchRenamer.for_starting_rename_process(branch_name: template_repo.default_branch, repository: repo)
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        renamer.start_rename("develop", actor: @owner, entry_point: :test_case)
      end
      payload = full_repository(repo.reload)
      assert_equal "develop", payload["default_branch"]
    end

    test "it includes if discussions are enabled or not" do
      output = full_repository(@repo)

      assert output["has_discussions"]
    end
  end

  context "#simple_repository_hash" do
    test "payload is valid" do
      output = simple_repository(@repo)
      assert output.key?("id")
      assert output.key?("node_id")
      assert output.key?("name")
      assert output.key?("full_name")

    end

    test "returns nil when no repo" do
      assert_nil simple_repository(nil)
    end

    test "returns nil when repo has no network" do
      @repo.stubs(:network).returns(nil)
      assert_nil simple_repository(@repo)
    end
  end

  context "#blob_content_hash" do
    test "payload is valid" do
      blob = TreeEntry.new(@repo, {
        "type" => "blob",
        "oid" => "0baac26be61a8cc8dd90567a175feda900ff73fc",
        "path" => "README.md",
        "data" => "contents"
      })

      output = blob_content(blob, repo: @repo)
      assert output.key?("type")
      assert output.key?("html_url")
      assert output.key?("download_url")
      assert output.key?("git_url")
      refute output.key?("content")
      refute output.key?("encoding")
    end

    test "full payload is valid" do
      blob = TreeEntry.new(@repo, {
        "type" => "blob",
        "oid" => "0baac26be61a8cc8dd90567a175feda900ff73fc",
        "path" => "README.md",
        "data" => "contents"
      })

      output = blob_content(blob, repo: @repo, full: true)
      assert output.key?("type")
      assert output.key?("html_url")
      assert output.key?("download_url")
      assert output.key?("git_url")
      assert output.key?("content")
      assert output.key?("size")
      assert output.key?("encoding")
    end

    test "symlink content is valid" do
      blob_info = {
        "type" => "blob",
        "oid" => "0baac26be61a8cc8dd90567a175feda900ff73fc",
        "path" => "README.md",
        "data" => "contents"
      }
      blob = TreeEntry.new(@repo, blob_info)

      symlink = TreeEntry.new(@repo, {
        "type" => "blob",
        "oid" => "1baac26be61a8cc8dd90567a175feda900ff73fd",
        "path" => "docs/README.md",
        "data" => "../README.md",
        "symlink_target" => blob,
        "symlink_target_object" => blob_info
      })
      symlink.stubs(:symlink?).returns(true)
      @repo.stubs(:tree_entry).returns(blob)

      output = blob_content(symlink, repo: @repo, full: true, sha: @repo.heads["master"].commit.tree_oid)
      assert_equal Base64.encode64("contents"), output["content"]
    end
  end

  context "#tree_object_content_hash" do
    test "payload is valid" do
      tree_object = TreeEntry.new(@repo, {
        "type" => "tree",
        "oid"  => @repo.heads["master"].commit.tree_oid,
        "path" => "",
      })

      output = tree_object_content(tree_object, repo: @repo)
      assert output.key?("name")
      assert output.key?("path")
      assert output.key?("sha")
      assert output.key?("size")
    end

    test "returns nil if tree object is nil" do
      assert_nil tree_object_content(nil)
    end
  end

  context "#disabled_repository_hash" do
    test "block creation date is in UTC - not the calling users zone" do
      @owner.time_zone = ActiveSupport::TimeZone["Central Time (US & Canada)"]
      output = disabled_repository(@disabled_repo)

      assert output["block"]["created_at"].include? "Z"
    end

    test "uses default message for repo disabled due to billing issue" do
      message = "Repository access blocked"
      org  = create :organization
      repo = create(:private_repository, owner: org)

      org.disable! # same as locking org for billing

      output = disabled_repository(repo, current_user: create(:user))

      assert_equal message, output["message"]
    end
  end

  context "#repository_invitation_hash" do
    test "renders a repository invitation with created_at in UTC" do
      output = repository_invitation(@invitation)
      assert_equal @invitation.created_at.iso8601, output["created_at"]
    end
  end

  context "#repository_hash" do
    test "renders beta format when beta media type is requested" do
      api_media_type "application/vnd.github.beta+json"

      output = repository(@repo)
      assert_equal "master", output["default_branch"]
      assert_equal "master", output["master_branch"]
    end

    test "renders v3 format when v3 media type is requested" do
      output = repository(@repo)
      assert_equal "master", output["default_branch"]
      refute output.key?("master_branch"),
      "Expected v3 output to omit 'master_branch' property"
    end

    test "renders default_branch when beta media type is requested and changeset is active" do
      api_media_type "application/vnd.github.beta+json"
      with_changeset "deprecate_beta_media_type" do
        output = repository(@repo)
        assert_equal "master", output["default_branch"]
        refute output.key?("master_branch")
      end
    end

    test "populates default_branch for empty repositories" do
      result = Repository.handle_creation(@owner, @owner.login, { name: "empty-repo" })
      assert result.success
      repo = Repository.nwo("#{@owner.login}/empty-repo")
      assert repo.empty?

      output = repository(repo)
      assert_equal repo.default_branch, output["default_branch"]
    end

    test "excludes permissions by default" do
      output = repository(@repo)
      refute output.key?("permissions"),
        "Expected default output to omit 'permissions' property"
    end

    test "the is_template key is present" do
      options = {
        show_template_repository: true
      }
      output = repository(@repo, options)

      assert output.key?("is_template")
    end

    test "includes permissions when current_user is given" do
      output = repository(@repo, current_user: @rando)
      permissions = output["permissions"]
      refute_nil permissions
      assert_equal false, permissions["admin"]
      assert_equal false, permissions["maintain"]
      assert_equal false, permissions["push"]
      assert_equal false, permissions["triage"]
      assert_equal true, permissions["pull"]
    end

    test "returns admin permissions" do
      output = repository(@priv_repo, current_user: @owner)
      permissions = output["permissions"]
      refute_nil permissions
      assert_equal true, permissions["admin"]
      assert_equal true, permissions["maintain"]
      assert_equal true, permissions["push"]
      assert_equal true, permissions["triage"]
      assert_equal true, permissions["pull"]
    end

    test "returns all permissions as false when user is not a member" do
      output = repository(@priv_repo, current_user: @rando)
      permissions = output["permissions"]
      refute_nil permissions
      assert_equal false, permissions["admin"]
      assert_equal false, permissions["maintain"]
      assert_equal false, permissions["push"]
      assert_equal false, permissions["triage"]
      assert_equal false, permissions["pull"]
    end

    test "returns triage level permissions" do
      @org.add_member(@rando, adder: @org.admins.first, action: :write)
      @org_repo.add_member(@rando, action: :triage)

      output = repository(@org_repo, current_user: @rando)
      permissions = output["permissions"]
      refute_nil permissions
      assert_equal false, permissions["admin"]
      assert_equal false, permissions["maintain"]
      assert_equal false, permissions["push"]
      assert_equal true, permissions["triage"]
      assert_equal true, permissions["pull"]
    end

    test "reports correct permission to internal repo for business member via org membership" do
      output = repository(@internal_repo, current_user: @other_biz_user)
      permissions = output["permissions"]
      refute_nil permissions
      assert_equal false, permissions["admin"]
      assert_equal false, permissions["maintain"]
      assert_equal false, permissions["push"]
      assert_equal false, permissions["triage"]
      assert_equal true, permissions["pull"]
    end

    test "reports correct permission to internal repo for business member via direct business membership" do
      output = repository(@internal_repo, current_user: @biz_owner)
      permissions = output["permissions"]
      refute_nil permissions
      assert_equal false, permissions["admin"]
      assert_equal false, permissions["maintain"]
      assert_equal false, permissions["push"]
      assert_equal false, permissions["triage"]
      assert_equal true, permissions["pull"]
    end

    test "does not include deprecated use_squash_pr_title_as_default if changeset active" do
      output = repository(@internal_repo, current_user: @biz_owner, show_merge_settings: true)
      assert output.has_key?("use_squash_pr_title_as_default")

      with_changeset "remove_use_squash_pr_title_as_default" do
        output = repository(@internal_repo, current_user: @biz_owner, show_merge_settings: true)
        refute output.has_key?("use_squash_pr_title_as_default")
      end
    end

    context "temp_clone_token" do
      test "excludes temp_clone_token by default" do
        output = repository(@repo)
        refute output.key?("temp_clone_token"),
          "Expected default output to omit 'temp_clone_token' property"
      end
    end

    test "includes the license" do
      RepositoryLicense.create! repository: @repo, license_id: 13
      @repo.reload
      output = repository(@repo, license: true)

      assert output.has_key?("license")
      refute_nil output["license"]
      assert_equal "mit", output["license"]["key"]
      assert_equal "MIT License", output["license"]["name"]
      assert_equal "MIT", output["license"]["spdx_id"]
    end

    test "doesn't link to hidden licenses" do
      RepositoryLicense.create! repository: @repo, license_id: 0
      @repo.reload
      output = repository(@repo, license: true)

      assert output.has_key?("license")
      refute_nil output["license"]
      assert_equal "other", output["license"]["key"]
      assert_equal "Other", output["license"]["name"]
      assert_equal "NOASSERTION", output["license"]["spdx_id"]
      assert_nil output["license"]["url"]
    end

    test "gracefully handles nil simple_repository_hash" do
      @repo.stubs(:network).returns(nil)
      assert_nil repository(@repo)
    end

    context "anonymous git access" do
      test "does not include anonymous git access if feature is disabled" do
        GitHub.stubs(:anonymous_git_access_available?).returns(true)
        GitHub.disable_anonymous_git_access(@repo.owner)

        output = repository(@repo)
        refute output.has_key?("anonymous_access_enabled")
      end

      test "includes anonymous git access" do
        GitHub.stubs(:anonymous_git_access_available?).returns(true)
        GitHub.enable_anonymous_git_access(@repo.owner)

        @repo.enable_anonymous_git_access(@repo.owner)
        @repo.reload
        output = repository(@repo)

        # Not enabled for now since the schema validation fails since it can't handle
        # runtime changes due to stubbing GitHub.anonymous_git_access_available?
        assert output.has_key?("anonymous_access_enabled")
        assert_equal true, output["anonymous_access_enabled"]

        @repo.disable_anonymous_git_access(@repo.owner)
        @repo.reload
        output = repository(@repo)

        # Not enabled for now since the schema validation fails since it can't handle
        # runtime changes due to stubbing GitHub.anonymous_git_access_available?
        assert output.has_key?("anonymous_access_enabled")
        assert_equal false, output["anonymous_access_enabled"]
      end
    end
  end

  context "#condensed_diff_entry_hash" do
    test "payload is valid" do
      diff_entry = GitHub::Diff.new(@repo,
        "c1800491d95c42b4e96fb83f31fe8d9230c62907",
        "7fd43660b371e21bc2aa306fad0fbff59829aae3").first
      output = condensed_diff_entry(diff_entry, repo: @repo)
      assert_equal({
        "sha" => "78981922613b2afb6025042ff6bd878ac1994e85",
        "filename" => "a",
        "status" => "modified",
        "additions" => 1,
        "deletions" => 0,
        "changes" => 1,
        "blob_url" =>  "https://github.com/owner/Kunze-Smith/blob/7fd43660b371e21bc2aa306fad0fbff59829aae3/a",
        "raw_url" =>  "https://github.com/owner/Kunze-Smith/raw/7fd43660b371e21bc2aa306fad0fbff59829aae3/a",
        "contents_url" =>  "#{GitHub.api_url}/repos/owner/Kunze-Smith/contents/a?ref=7fd43660b371e21bc2aa306fad0fbff59829aae3",
        "patch" => "@@ -0,0 +1 @@\n+a",
      }, output)

    end

    test "with a submodule in the diff" do
      diff_entry = GitHub::Diff.new(@submodule_repo,
        "c0a4348b5f94baae07dd5787c8c902842ee39de4",
        "e5631fbeb54c8e5133285eecf9d98e51f78e7494").first

      output = condensed_diff_entry(diff_entry, repo: @submodule_repo)

      assert_nil output["blob_url"]
      assert_nil output["raw_url"]
      assert output.has_key?("blob_url")
      assert output.has_key?("raw_url")
    end

    test "with no submodules in diff" do
      diff_entry = GitHub::Diff.new(@repo,
        "c1800491d95c42b4e96fb83f31fe8d9230c62907",
        "7fd43660b371e21bc2aa306fad0fbff59829aae3").first

      output = condensed_diff_entry(diff_entry, repo: @repo)

      assert_equal({
        "sha" => "78981922613b2afb6025042ff6bd878ac1994e85",
        "filename" => "a",
        "status" => "modified",
        "additions" => 1,
        "deletions" => 0,
        "changes" => 1,
        "blob_url" =>  "https://github.com/owner/Kunze-Smith/blob/7fd43660b371e21bc2aa306fad0fbff59829aae3/a",
        "raw_url" =>  "https://github.com/owner/Kunze-Smith/raw/7fd43660b371e21bc2aa306fad0fbff59829aae3/a",
        "contents_url" =>  "#{GitHub.api_url}/repos/owner/Kunze-Smith/contents/a?ref=7fd43660b371e21bc2aa306fad0fbff59829aae3",
        "patch" => "@@ -0,0 +1 @@\n+a",
      }, output)
    end
  end

  context "#content_hash" do
    test "the html_url gets encoded correctly" do
      _, trees, _ = @repo.tree_entries(@repo.default_oid, "")
      tree = trees.first

      # when the tree is a blob
      tree.stubs(:path).returns("!@#$%^&*()?.md")
      output = content(tree, { repo: @repo })
      assert_equal "https://github.com/#{@repo.nwo}/blob/master/!@%23$%25%5E&*()%3F.md", output["html_url"]

      # when the tree is a tree
      tree.stubs(:path).returns("!@#$%^&*()?")
      tree.stubs(:blob?).returns(false)
      output = content(tree, { repo: @repo })
      assert_equal "https://github.com/#{@repo.nwo}/tree/master/!@%23$%25%5E&*()%3F", output["html_url"]

      # when the path contains special characters
      tree.stubs(:path).returns("情沉拐捨.md")
      tree.unstub(:blob?)
      output = content(tree, { repo: @repo })
      assert_equal "https://github.com/#{@repo.nwo}/blob/master/%E6%83%85%E6%B2%89%E6%8B%90%E6%8D%A8.md", output["html_url"]

      tree.stubs(:path).returns("情沉拐捨")
      tree.stubs(:blob?).returns(false)
      output = content(tree, { repo: @repo })
      assert_equal "https://github.com/#{@repo.nwo}/tree/master/%E6%83%85%E6%B2%89%E6%8B%90%E6%8D%A8", output["html_url"]
    end

    test "the url gets encoded correctly" do
      _, trees, _ = @repo.tree_entries(@repo.default_oid, "")
      tree = trees.first
      base_url = Api::Serializer.url("/repos/#{@repo.nwo}/contents/")

      # when the tree is a blob
      tree.stubs(:path).returns("!@#$%^&*()?.md")
      output = content(tree, { repo: @repo })

      assert_equal "#{base_url}!@%23$%25%5E&*()%3F.md?ref=master", output["url"]

      # when the tree is a tree
      tree.stubs(:path).returns("!@#$%^&*()?")
      tree.stubs(:blob?).returns(false)
      output = content(tree, { repo: @repo })
      assert_equal "#{base_url}!@%23$%25%5E&*()%3F?ref=master", output["url"]

      # when the path contains special characters
      tree.stubs(:path).returns("情沉拐捨.md")
      tree.unstub(:blob?)
      output = content(tree, { repo: @repo })
      assert_equal "#{base_url}%E6%83%85%E6%B2%89%E6%8B%90%E6%8D%A8.md?ref=master", output["url"]

      tree.stubs(:path).returns("情沉拐捨")
      tree.stubs(:blob?).returns(false)
      output = content(tree, { repo: @repo })
      assert_equal "#{base_url}%E6%83%85%E6%B2%89%E6%8B%90%E6%8D%A8?ref=master", output["url"]
    end
  end

  SimpleRepoQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
    query($owner: String!, $name: String!) {
      repository(name: $name, owner: $owner) {
        ...Api::Serializer::RepositoriesDependency::SimpleRepositoryFragment
      }
    }
  GRAPHQL

  context "#graphql_simple_repository_hash" do
    test "renders a repository" do
      results = Api::App::PlatformClient.query(SimpleRepoQuery, variables: {
        "name" => @repo.name, "owner" => @repo.owner.login
      })
      output = Api::Serializer.serialize(:graphql_simple_repository_hash, results.data.repository)

      assert_equal output[:name], @repo.name
      assert_equal output[:owner][:login], @repo.owner.login
      refute output[:fork]
      refute output[:private]
      assert_equal output[:url], "#{GitHub.api_url}/repos/#{@repo.name_with_owner}"
    end

    test "returns nil if repo is nil" do
      assert_nil Api::Serializer.serialize(:graphql_simple_repository_hash, nil)
    end

    test "returns nil if repo does not have network" do
      ::Repository.any_instance.stubs(:network).returns(nil)

      results = Api::App::PlatformClient.query(SimpleRepoQuery, variables: {
        "name" => @repo.name, "owner" => @repo.owner.login
      })
      output = Api::Serializer.serialize(:graphql_simple_repository_hash, results.data.repository)

      assert_nil output
    end
  end

  FullRepoQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
    query($owner: String!, $name: String!) {
      repository(name: $name, owner: $owner) {
        ...Api::Serializer::RepositoriesDependency::ExtendedRepositoryFragment
      }
    }
  GRAPHQL

  context "#graphql_full_repository_hash" do
    test "the template_repository key is present" do
      variables = {
        name: @repo.name,
        owner: @repo.owner.login,
        enterprise: GitHub.enterprise?,
      }
      options = {
        show_template_repository: true
      }
      results = Api::App::PlatformClient.query(FullRepoQuery, variables: variables,
                                               context: { viewer: @repo.owner })
      output = graphql_full_repository(results.data.repository, options)

      assert output.key?("template_repository")
    end
  end

  RepoQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
    query($owner: String!, $name: String!) {
      repository(name: $name, owner: $owner) {
        ...Api::Serializer::RepositoriesDependency::RepositoryFragment
      }
    }
  GRAPHQL

  context "#graphql_repository_hash" do
    context "anonymous git access" do
      test "does not include anonymous git access if feature is disabled" do
        GitHub.stubs(:anonymous_git_access_available?).returns(true)
        GitHub.disable_anonymous_git_access(@repo.owner)

        variables = {
          name: @repo.name,
          owner: @repo.owner.login,
          enterprise: GitHub.enterprise?,
        }

        results = Api::App::PlatformClient.query(RepoQuery, variables: variables, context: { viewer: @repo.owner })
        output = graphql_repository(results.data.repository)

        refute output.has_key?("anonymous_access_enabled")
      end

      test "includes anonymous git access" do
        GitHub.stubs(:anonymous_git_access_available?).returns(true)
        GitHub.enable_anonymous_git_access(@repo.owner)

        variables = {
          name: @repo.name,
          owner: @repo.owner.login,
          enterprise: GitHub.enterprise?,
        }

        @repo.enable_anonymous_git_access(@repo.owner)
        @repo.reload
        results = Api::App::PlatformClient.query(RepoQuery, variables: variables, context: { viewer: @repo.owner })
        output = graphql_repository(results.data.repository)

        assert output.has_key?("anonymous_access_enabled")
        assert_equal true, output["anonymous_access_enabled"]

        @repo.disable_anonymous_git_access(@repo.owner)
        @repo.reload
        results = Api::App::PlatformClient.query(RepoQuery, variables: variables, context: { viewer: @repo.owner })
        output = graphql_repository(results.data.repository)

        assert output.has_key?("anonymous_access_enabled")
        assert_equal false, output["anonymous_access_enabled"]
      end
    end

    test "the is_template key is present" do
      variables = {
        name: @repo.name,
        owner: @repo.owner.login,
        enterprise: GitHub.enterprise?,
      }
      results = Api::App::PlatformClient.query(RepoQuery, variables: variables,
                                               context: { viewer: @repo.owner })
      output = graphql_repository(results.data.repository)

      assert output.key?("is_template")
    end
  end

  context "#community_profile_hash" do
    test "payload is valid with no community files" do
      community_profile = CommunityProfile.create! repository: @repo
      output = community_profile(community_profile)
      assert_same_elements %w[health_percentage description documentation files updated_at], output.keys
      refute output["files"]["code_of_conduct"]
    end

    test "payload is valid with all files" do
      repo = create :repository, owner: @owner, from_example: :community_files
      community_profile = CommunityProfile.create! repository: repo
      output = community_profile(community_profile)
      assert_same_elements %w[health_percentage description documentation files updated_at], output.keys

    end

    test "payload is valid for org with content reports enabled" do
      repo = create(:repository, :org_owned)
      community_profile = create(:community_profile, repository: repo)
      repo.enable_tiered_reporting(actor: repo.owner.admin)

      output = community_profile(community_profile)
      assert output["content_reports_enabled"]
    end

    test "works for repo with org level health files" do
      org = create(:organization)
      org_repo = create(:repository, owner: org)
      dot_github_repo = create(:repository, owner: org, name: ".github", from_example: :community_files)
      org_repo_community_profile = create(:community_profile, repository: org_repo)

      output = community_profile(org_repo_community_profile)
      assert_match /#{dot_github_repo.name_with_owner}/, output["files"]["code_of_conduct"]["html_url"]
      assert_match /#{dot_github_repo.name_with_owner}/, output["files"]["pull_request_template"]["html_url"]
    end
  end

  context "#page_build_hash" do
    test "payload is valid" do
      output = page_build(@build)
      assert output.key?("url")
      assert output.key?("status")
      assert output.key?("error")
      assert output.key?("pusher")

    end
  end

  context "#page_hash" do
    test "payload is valid" do
      options = {
        html_url: @repo.gh_pages_url,
        repo: @repo,
      }
      output = page(@page, options)
      assert output.key?("url")
      assert output.key?("status")
      assert output.key?("cname")
      assert output.key?("custom_404")
    end

    test "certificate domains are correct for project page", skip_enterprise: true do
      GitHub.flipper[:pages_health_check].enable

      page = create :page, :with_certificate, owner: @owner, cname: "example.com"
      options = {
        html_url: page.repository.gh_pages_url,
        repo: page.repository,
      }
      output = page(page, options)
      assert_equal output["cname"], "example.com"
      assert output.key?("https_certificate")
      assert_includes output["https_certificate"]["domains"], "example.com"
    end

    test "certificate domains inherit from user page", skip_enterprise: true do
      GitHub.flipper[:pages_health_check].enable

      create :user_page, :with_certificate, owner: @owner, cname: "example.com"
      options = {
        html_url: @repo.gh_pages_url,
        repo: @repo,
      }
      output = page(@page, options)
      assert_nil output["cname"]
      assert output.key?("https_certificate")
      assert_includes output["https_certificate"]["domains"], "example.com"
    end
  end

  context "#simple_repository_ruleset_hash" do
    test "payload is valid" do
      ruleset = create(:repository_ruleset, source: @org_repo)

      hash = simple_repository_ruleset(ruleset, request_source: @org_repo)
      elements = %w[id name target source_type source enforcement node_id _links created_at updated_at]

      assert_same_elements elements, hash.keys
      refute hash.key?("rules")
      refute hash.key?("conditions")
    end

    test "exclude business member privilege ruleset html url when user is not a business owner" do
      GitHub.flipper[:member_privilege_rulesets].enable
      GitHub.flipper[:enterprise_rulesets].enable

      biz = @internal_repo.owner.business
      org = @internal_repo.owner
      user = create(:user)
      ruleset = create(:repository_ruleset, :targets_all_orgs, :repository_policy, source: biz)
      org.add_member(user)
      hash = simple_repository_ruleset(ruleset, request_source: @internal_repo, current_user: user)
      # rest api url
      assert_includes hash["_links"]["self"]["href"], "#{@internal_repo.nwo}/rulesets/#{ruleset.id}"
      assert_nil hash["_links"]["html"]
    end

    test "include business member privilege ruleset html url when user is a business owner" do
      GitHub.flipper[:member_privilege_rulesets].enable
      GitHub.flipper[:enterprise_rulesets].enable

      biz = @internal_repo.owner.business
      admin = biz.admins.first
      ruleset = create(:repository_ruleset, :targets_all_orgs, :repository_policy, source: biz)
      hash = simple_repository_ruleset(ruleset, request_source: @internal_repo, current_user: admin)
      # rest api url
      assert_includes hash["_links"]["self"]["href"], "#{@internal_repo.nwo}/rulesets/#{ruleset.id}"
      # URL for editing enterprise ruleset
      assert_includes hash["_links"]["html"]["href"], "#{biz.slug}/settings/policies/repositories/#{ruleset.id}"
    end

    test "exclude org member privilege ruleset html url when user cannot modify the ruleset" do
      GitHub.flipper[:member_privilege_rulesets].enable
      GitHub.flipper[:enterprise_rulesets].enable

      org = @internal_repo.owner
      user = create(:user)
      ruleset = create(:repository_ruleset, :repository_policy, source: org)
      org.add_member(user)
      hash = simple_repository_ruleset(ruleset, request_source: @internal_repo, current_user: user)
      # rest api url
      assert_includes hash["_links"]["self"]["href"], "#{@internal_repo.nwo}/rulesets/#{ruleset.id}"
      assert_nil hash["_links"]["html"]
    end

    test "include org member privilege ruleset html url when user can modify the ruleset" do
      GitHub.flipper[:member_privilege_rulesets].enable
      GitHub.flipper[:enterprise_rulesets].enable

      biz = @internal_repo.owner.business
      org = @internal_repo.owner
      admin = org.admins.first
      ruleset = create(:repository_ruleset, :repository_policy, source: org)
      hash = simple_repository_ruleset(ruleset, request_source: @internal_repo, current_user: admin)
      # rest api url
      assert_includes hash["_links"]["self"]["href"], "#{@internal_repo.nwo}/rulesets/#{ruleset.id}"
      # URL for editing org ruleset
      assert_includes hash["_links"]["html"]["href"], "#{org.display_login}/settings/policies/repositories/#{ruleset.id}"
    end

    test "include readonly repo ruleset url at repo level when user cannot modify the ruleset" do
      GitHub.flipper[:member_privilege_rulesets].enable
      GitHub.flipper[:enterprise_rulesets].enable

      org = @internal_repo.owner
      user = create(:user)
      ruleset = create(:repository_ruleset, :targets_all_repos, target: :branch, source: org)
      org.add_member(user)
      hash = simple_repository_ruleset(ruleset, request_source: @internal_repo, current_user: user)
      # rest api url
      assert_includes hash["_links"]["self"]["href"], "#{@internal_repo.nwo}/rulesets/#{ruleset.id}"
      # URL at repo level
      assert_includes hash["_links"]["html"]["href"], "#{@internal_repo.nwo}/rules/#{ruleset.id}"
    end

    test "include readonly repo ruleset url at repo level when user can modify the ruleset" do
      GitHub.flipper[:member_privilege_rulesets].enable
      GitHub.flipper[:enterprise_rulesets].enable

      biz = @internal_repo.owner.business
      org = @internal_repo.owner
      admin = org.admins.first
      ruleset = create(:repository_ruleset, :targets_all_repos, target: :branch, source: org)
      hash = simple_repository_ruleset(ruleset, request_source: @internal_repo, current_user: admin)
      # rest api url
      assert_includes hash["_links"]["self"]["href"], "#{@internal_repo.nwo}/rulesets/#{ruleset.id}"
      # URL at repo level
      assert_includes hash["_links"]["html"]["href"], "#{@internal_repo.nwo}/rules/#{ruleset.id}"
    end

    test "exclude org edit ruleset url at org level when user cannot modify the ruleset" do
      GitHub.flipper[:member_privilege_rulesets].enable
      GitHub.flipper[:enterprise_rulesets].enable

      biz = @internal_repo.owner.business
      org = @internal_repo.owner
      user = create(:user)
      org.add_member(user)
      ruleset = create(:repository_ruleset, :targets_all_repos, target: :branch, source: org)
      hash = simple_repository_ruleset(ruleset, request_source: org, current_user: user)
      # rest api url
      assert_includes hash["_links"]["self"]["href"], "#{org.display_login}/rulesets/#{ruleset.id}"
      assert_nil hash["_links"]["html"]
    end

    test "include org edit ruleset url at org level when user can modify the ruleset" do
      GitHub.flipper[:member_privilege_rulesets].enable
      GitHub.flipper[:enterprise_rulesets].enable

      org = @internal_repo.owner
      admin = org.admins.first
      ruleset = create(:repository_ruleset, :targets_all_repos, target: :branch, source: org)
      hash = simple_repository_ruleset(ruleset, request_source: org, current_user: admin)
      # rest api url
      assert_includes hash["_links"]["self"]["href"], "#{org.display_login}/rulesets/#{ruleset.id}"
      # URL for editing org ruleset
      assert_includes hash["_links"]["html"]["href"], "#{org.display_login}/settings/rules/#{ruleset.id}"
    end
  end

  context "#repository_ruleset_hash" do
    test "payload is valid" do
      ruleset = create(:repository_ruleset, source: @org_repo)

      hash = repository_ruleset(ruleset, request_source: @org_repo, current_user: @rando)

      expected = %w[id name target source_type source enforcement node_id rules conditions _links created_at updated_at current_user_can_bypass]
      assert_same_elements expected, hash.keys
    end

    test "payload indicates current user can bypass when appropriate" do
      ruleset = create(:repository_ruleset, :targets_all_repos, :targets_all_branches, source: @org)
      hash = repository_ruleset(ruleset, request_source: @org_repo, current_user: @org_admin)

      assert_equal hash["current_user_can_bypass"], "never"

      bypass_actor = RepositoryRulesetBypassActor.new(
        repository_ruleset: ruleset,
        actor: RepositoryRole.find_by(name: "admin", owner: nil),
        bypass_mode: RepositoryRulesetBypassActor::BYPASS_MODES[:pull_request],
      )
      bypass_actor.save!

      hash = repository_ruleset(ruleset.reload, request_source: @org_repo, current_user: @org_admin)
      assert_equal hash["current_user_can_bypass"], "pull_requests_only"

      bypass_actor.update!(bypass_mode: RepositoryRulesetBypassActor::BYPASS_MODES[:any])
      hash = repository_ruleset(ruleset.reload, request_source: @org_repo, current_user: @org_admin)

      assert_equal hash["current_user_can_bypass"], "always"
    end

    test "payload does not contain current user bypass info if request_source is not a repo" do
      ruleset = create(:repository_ruleset, source: @org)

      hash = repository_ruleset(ruleset, request_source: @org, current_user: @rando)

      elements = %w[id name target source_type source enforcement node_id rules conditions _links created_at updated_at]

      assert_same_elements elements, hash.keys
      refute_includes hash.keys, "current_user_can_bypass"
    end

    test "payload includes deploy key bypass actor" do
      ruleset = create(:repository_ruleset, :deploy_key_bypass, source: @org)

      hash = repository_ruleset(ruleset, request_source: @org, current_user: @org_admin)
      assert_same_hash({
        "actor_id" => RepositoryRulesetBypassActor::DeployKey.id,
        "actor_type" => RepositoryRulesetBypassActor::DeployKey.type,
        "bypass_mode" => "always"
      }, hash["bypass_actors"][0])
    end
  end

  context "#repository_rule_condition_hash" do
    test "payload does not return any conditions if no request source is provided" do
      # if we dont know the request source, we shouldn't return the condition to avoid leaking information
      ruleset = create(:repository_ruleset, source: @org_repo)
      condition = create(:repository_rule_condition, :targets_default_branch)

      hash = repository_rule_condition(condition)

      assert_equal 0, hash.size
    end

    test "payload does not return non-refname conditions when the request source is a repository" do
      @org.plan = "business_plus"
      ruleset = create(:repository_ruleset, source: @org)
      condition = create(:repository_rule_condition, repository_ruleset: ruleset, target: "repository_name", parameters: {
        include: ["prod*"],
        exclude: []
      })

      hash = repository_rule_condition(condition, request_source: @org_repo)

      assert_empty hash.keys
    end

    test "payload returns non-refname conditions when the request source is an organization" do
      @org.plan = "business_plus"
      ruleset = create(:repository_ruleset, source: @org)
      condition = create(:repository_rule_condition, repository_ruleset: ruleset, target: "repository_name", parameters: {
        include: ["prod*"],
        exclude: []
      })
      hash = repository_rule_condition(condition, request_source: @org_repo.organization)

      assert_same_elements ["repository_name"], hash.keys
      assert_same_elements %w[include exclude], hash["repository_name"].keys
    end

    test "payload does not return any conditions when no request source is specified" do
      # if we dont know the request source, we shouldn't return the condition to avoid leaking information
      ruleset = create(:repository_ruleset, source: @org_repo)
      condition = create(:repository_rule_condition, :targets_all_branches, repository_ruleset: ruleset)

      hash = repository_rule_condition(condition, request_source: nil)

      assert_empty hash.keys
    end
  end

  context "#repository_rule_hash" do
    test "payload is valid" do
      # metadata pattern requires enterprise tier
      @org_repo.plan = "business_plus"
      ruleset = create(:repository_ruleset, source: @org_repo)
      rule = create(:repository_rule_configuration, :metadata_pattern, repository_ruleset: ruleset)

      hash = repository_rule(rule)

      assert_same_elements %w[type parameters], hash.keys
    end
  end

  context "#repository_rule_with_ruleset_source_hash" do
    test "payload is valid" do
      # metadata pattern requires enterprise tier
      @org_repo.plan = "business_plus"
      ruleset = create(:repository_ruleset, source: @org_repo)
      rule = create(:repository_rule_configuration, :metadata_pattern, repository_ruleset: ruleset)

      hash = repository_rule_with_ruleset_source(rule)

      assert_same_elements %w[type parameters ruleset_source_type ruleset_source ruleset_id], hash.keys
    end
  end
end

class RepoSerializersMultiTenantTest < Api::SerializerTestCase
  fixtures do
    on_multi_tenant_enterprise do
      @owner = create :emu
      @business = @owner.enterprise_managed_business
      @org = create :organization, business: @business, admin: @owner
      @repo = create :repository, organization: @org
    end
  end

  setup do
    on_multi_tenant_enterprise(tenant: @business)
  end

  context "#simple_repository_hash" do
    test "returns url with display login value for external calls" do
      output = simple_repository(@repo)

      refute_equal @repo.name_with_owner, @repo.name_with_display_owner
      assert_includes output["url"], @repo.name_with_display_owner
    end

    test "returns url with unique login value for internal calls" do
      GitHub.stubs(:proxima_internal_api_unique_logins_required?).returns(true)

      output = simple_repository(@repo)

      refute_equal @repo.name_with_owner, @repo.name_with_display_owner
      assert_includes output["url"], @repo.name_with_owner
    end
  end

  context "#full_repository_hash" do
    test "returns url with display login value for external calls" do
      output = full_repository(@repo)

      refute_equal @repo.name_with_owner, @repo.name_with_display_owner

      refute_includes output["url"], @repo.name_with_owner
      refute_includes output["git_url"], @repo.name_with_owner
      refute_includes output["ssh_url"], @repo.name_with_owner
      refute_includes output["clone_url"], @repo.name_with_owner
      refute_includes output["svn_url"], @repo.name_with_owner

      assert_includes output["url"], @repo.name_with_display_owner
      assert_includes output["git_url"], @repo.name_with_display_owner
      assert_includes output["ssh_url"], @repo.name_with_display_owner
      assert_includes output["clone_url"], @repo.name_with_display_owner
      assert_includes output["svn_url"], @repo.name_with_display_owner
    end

    test "returns url with unique login value for internal calls without serialize login option" do
      GitHub.stubs(:proxima_internal_api_unique_logins_required?).returns(true)

      output = full_repository(@repo)

      refute_equal @repo.name_with_owner, @repo.name_with_display_owner
      assert_includes output["url"], @repo.name_with_owner
      assert_includes output["git_url"], @repo.name_with_owner
      assert_includes output["ssh_url"], @repo.name_with_owner
      assert_includes output["clone_url"], @repo.name_with_owner
      assert_includes output["svn_url"], @repo.name_with_owner
    end

    test "returns url with display login value for internal calls with serialize login set to display" do
      GitHub.stubs(:proxima_internal_api_unique_logins_required?).returns(true)

      output = full_repository(@repo, serialize_login: :display)

      refute_equal @repo.name_with_owner, @repo.name_with_display_owner

      refute_includes output["url"], @repo.name_with_owner
      refute_includes output["git_url"], @repo.name_with_owner
      refute_includes output["ssh_url"], @repo.name_with_owner
      refute_includes output["clone_url"], @repo.name_with_owner
      refute_includes output["svn_url"], @repo.name_with_owner

      assert_includes output["url"], @repo.name_with_display_owner
      assert_includes output["git_url"], @repo.name_with_display_owner
      assert_includes output["ssh_url"], @repo.name_with_display_owner
      assert_includes output["clone_url"], @repo.name_with_display_owner
      assert_includes output["svn_url"], @repo.name_with_display_owner
    end

    test "returns ssh url includes tenant slug" do
      output = full_repository(@repo, serialize_login: :display)

      refute output["ssh_url"].starts_with?("git@")
      assert output["ssh_url"].starts_with?("#{@business.slug}@")
    end

    test "returns all urls with tenant subdomain" do
      slug = @business.slug
      output = full_repository(@repo)
      assert_includes output["url"], "#{slug}.github.com"
      assert_includes output["svn_url"], "#{slug}.github.com"
      assert_includes output["owner"]["url"], "#{slug}.github.com"
    end
  end
end unless GitHub.single_business_environment?
