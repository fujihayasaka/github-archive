# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryTemplateDependencyTest < GitHub::TestCase
  context "templates_relevant_to scope" do
    test "includes template user recently cloned that's owned by another user" do
      user = create(:user)
      template = create(:repository, template: true)
      create(:repository_clone, cloning_user: user, template_repository: template)

      result = Repository.templates_relevant_to(user)

      assert_includes result, template
    end

    test "includes private template user recently cloned that's owned by another user" do
      user = create(:user)
      private_template = create(:private_repository, template: true)
      private_template.add_member(user)
      create(:repository_clone, cloning_user: user, template_repository: private_template)

      result = Repository.templates_relevant_to(user)

      assert_includes result, private_template
    end

    test "includes template owned by given user" do
      user = create(:user)
      template = create(:repository, template: true, owner: user)

      result = Repository.templates_relevant_to(user)

      assert_includes result, template
    end

    test "includes template owned by an org the user belongs to" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      template = create(:repository, template: true, owner: org)
      private_template = create(:private_repository, template: true, owner: org)

      result = Repository.templates_relevant_to(user)

      assert_includes result, template
      assert_includes result, private_template
    end

    test "includes template owned by the given org" do
      org = create(:organization)
      template = create(:repository, template: true, owner: org)

      result = Repository.templates_relevant_to(org)

      assert_includes result, template
    end

    test "includes template in org that is part of user's business but user isn't a member of the org" do
      template_org = create(:enterprise_linked_organization)
      internal_template = create(:repository, :org_owned_internal, template: true, owner: template_org)

      viewer_org = create(:enterprise_linked_organization, business: template_org.business)
      viewer = create(:user)

      viewer_org.add_member(viewer)

      result = Repository.templates_relevant_to(viewer)

      if GitHub.flipper[:indirect_orgs_for_repo_templates].enabled?
        assert_includes result, internal_template
      else
        refute_includes result, internal_template
      end
    end

    test "does not include template owned by another user that given user hasn't cloned" do
      user = create(:user)
      rando = create(:user)
      template = create(:repository, template: true, owner: rando)

      result = Repository.templates_relevant_to(user)

      refute_includes result, template
    end
  end

  context "#cloning_from_template?" do
    test "true for a repo being cloned from a template" do
      repo = create(:repository)
      create(:repository_clone, clone_repository: repo, state: :cloning)

      assert_predicate repo, :cloning_from_template?
    end

    test "true for a repo that errored while being cloned from a template" do
      repo = create(:repository)
      create(:repository_clone, clone_repository: repo, state: :error)

      assert_predicate repo, :cloning_from_template?
    end

    test "false for a repo that has finished being cloned" do
      repo = create(:repository)
      create(:repository_clone, :finished, clone_repository: repo)

      refute_predicate repo, :cloning_from_template?
    end

    test "false for a repo that was not cloned" do
      repo = create(:repository)

      refute_predicate repo, :cloning_from_template?
    end
  end

  context "#finished_cloning_from_template?" do
    test "false for a repo being cloned from a template" do
      repo = create(:repository)
      create(:repository_clone, clone_repository: repo, state: :cloning)

      refute_predicate repo, :finished_cloning_from_template?
    end

    test "false for a repo that errored while being cloned from a template" do
      repo = create(:repository)
      create(:repository_clone, clone_repository: repo, state: :error)

      refute_predicate repo, :finished_cloning_from_template?
    end

    test "true for a repo that has finished being cloned" do
      repo = create(:repository)
      create(:repository_clone, :finished, clone_repository: repo)

      assert_predicate repo, :finished_cloning_from_template?
    end

    test "false for a repo that was not cloned" do
      repo = create(:repository)

      refute_predicate repo, :finished_cloning_from_template?
    end
  end

  context "#clone_errored?" do
    test "false for a repo being cloned from a template" do
      repo = create(:repository)
      create(:repository_clone, clone_repository: repo, state: :cloning)

      refute_predicate repo, :clone_errored?
    end

    test "true for a repo that errored while being cloned from a template" do
      repo = create(:repository)
      create(:repository_clone, clone_repository: repo, state: :error)

      assert_predicate repo, :clone_errored?
    end

    test "false for a repo that has finished being cloned" do
      repo = create(:repository)
      create(:repository_clone, :finished, clone_repository: repo)

      refute_predicate repo, :clone_errored?
    end

    test "false for a repo that was not cloned" do
      repo = create(:repository)

      refute_predicate repo, :clone_errored?
    end
  end

  context "#template_repository" do
    test "returns the template repo the clone came from" do
      template_repo = create(:repository, template: true)
      repo_clone = create(:repository_clone, template_repository: template_repo)

      assert_equal template_repo, repo_clone.clone_repository.template_repository
    end

    test "returns nil when the repo did not come from a template" do
      repo = create(:repository)

      assert_nil repo.template_repository
    end
  end

  context "#lfs_cannot_template" do
    test "fails if an LFS repository is converted to template" do
      lfs_repo = create :repository
      # Let's simulate LFS content by just creating the blob, which is enough,
      # even if no git object points to it with an LFS pointer
      create :media_blob, repository_network: lfs_repo.network

      lfs_repo.template = true
      assert_raises ActiveRecord::RecordInvalid do
        lfs_repo.save!
      end
    end

    test "template repo can be updated even if it has LFS content" do
      repo = create :repository
      repo.template = true
      repo.save!

      # Currently there's no check that prevents pushing LFS to a template repo.
      create :media_blob, repository_network: repo.network

      # Reload to ensure has_lfs_files? is refreshed
      repo = Repositories::Public.find_active!(repo.id)
      repo.has_wiki = !repo.has_wiki
      repo.save!
    end
  end

  context "#clone_template_to" do
    test "clones the template repo to the given owner" do
      template_repo = create(:repository, template: true)

      owner, actor, name, copy_branches, description,
        visibility, reflog_data, orchestration = build_clone_template_to_stubs

      cloned_repo = stub("cloned_repo")

      owner.stubs(:organization?).returns(true)
      owner.stubs(:can_create_repository?).with(actor, visibility: visibility).returns(true)
      owner.stubs(:renaming?).returns(false)

      GitHub.stubs(:public_repositories_available?).returns(true)

      orchestration.expects(:valid?).returns(true)
      orchestration.expects(:execute)

      orchestration.stubs(:repository).returns(cloned_repo)
      orchestration.stubs(:failed?).returns(false)

      RepositoryOrchestration.expects(:clone_template).with(
        template_repository: template_repo,
        owner:,
        actor:,
        name:,
        copy_branches:,
        description:,
        visibility:,
        reflog_data:,
        current_integration_context: nil).returns(orchestration)

      repo_clone, reason, message = template_repo.clone_template_to(owner,
        actor:,
        name:,
        copy_branches:,
        description:,
        visibility:,
        reflog_data:,
        current_integration_context: nil
      )

      assert_equal cloned_repo, repo_clone
      assert_nil reason
      assert_nil message
    end

    test "returns :forbidden if can't write to owner" do
      template_repo = create(:repository, template: true)

      owner, actor, name, copy_branches, description,
        visibility, reflog_data, _ = build_clone_template_to_stubs

      owner.stubs(:organization?).returns(true)
      owner.stubs(:can_create_repository?).with(actor, visibility: visibility).returns(false)

      owner.stubs(:display_login).returns("owner")
      actor.stubs(:display_login).returns("actor")

      repo_clone, reason, message = template_repo.clone_template_to(owner,
        actor:,
        name:,
        copy_branches:,
        description:,
        visibility:,
        reflog_data:,
        current_integration_context: nil
      )

      assert_nil repo_clone
      assert_equal :forbidden, reason
      assert_equal "actor cannot create a repository for owner.", message
    end

    test "returns :forbidden if can't create public repos" do
      template_repo = create(:repository, template: true)

      owner, actor, name, copy_branches, description,
        visibility, reflog_data, _ = build_clone_template_to_stubs

      owner.stubs(:organization?).returns(true)
      owner.stubs(:can_create_repository?).with(actor, visibility: visibility).returns(true)

      GitHub.stubs(:public_repositories_available?).returns(false)

      visibility.stubs(:==).with(::Repository::PUBLIC_VISIBILITY).returns(true)

      repo_clone, reason, message = template_repo.clone_template_to(owner,
        actor:,
        name:,
        copy_branches:,
        description:,
        visibility:,
        reflog_data:,
        current_integration_context: nil
      )

      assert_nil repo_clone
      assert_equal :forbidden, reason
      assert_equal "Public repositories not permitted on #{GitHub.flavor}", message
    end

    test "returns :forbidden if owner is being renamed" do
      template_repo = create(:repository, template: true)

      owner, actor, name, copy_branches, description,
        visibility, reflog_data, _ = build_clone_template_to_stubs

      owner.stubs(:can_create_repository?).with(actor, visibility: visibility).returns(true)
      owner.stubs(:organization?).returns(true)
      owner.stubs(:renaming?).returns(true)

      GitHub.stubs(:public_repositories_available?).returns(true)

      owner.stubs(:display_login).returns("owner")
      actor.stubs(:display_login).returns("actor")

      repo_clone, reason, message = template_repo.clone_template_to(owner,
        actor:,
        name:,
        copy_branches:,
        description:,
        visibility:,
        reflog_data:,
        current_integration_context: nil
      )

      assert_nil repo_clone
      assert_equal :forbidden, reason
      assert_equal "#{owner.display_login} is currently renaming and cannot create new repositories.", message
    end

    test "returns :unprocessable_entity if orchestration is invalid" do
      template_repo = create(:repository, template: true)

      owner, actor, name, copy_branches, description,
        visibility, reflog_data, orchestration = build_clone_template_to_stubs

      owner.stubs(:organization?).returns(true)
      owner.stubs(:renaming?).returns(false)
      owner.stubs(:can_create_repository?).with(actor, visibility: visibility).returns(true)

      GitHub.stubs(:public_repositories_available?).returns(true)

      orchestration.expects(:valid?).returns(false)

      orchestration.expects(:errors).returns(stub(full_messages: ["error"]))

      RepositoryOrchestration.expects(:clone_template).with(
        template_repository: template_repo,
        owner:,
        actor:,
        name:,
        copy_branches:,
        description:,
        visibility:,
        reflog_data:,
        current_integration_context: nil).returns(orchestration)

      repo_clone, reason, message = template_repo.clone_template_to(owner,
        actor:,
        name:,
        copy_branches:,
        description:,
        visibility:,
        reflog_data:,
        current_integration_context: nil
      )

      assert_nil repo_clone
      assert_equal :unprocessable_entity, reason
      assert_equal "Could not clone: error", message
    end

    test "returns :unprocessable_entity if orchestration fails" do
      template_repo = create(:repository, template: true)

      owner, actor, name, copy_branches, description,
        visibility, reflog_data, orchestration = build_clone_template_to_stubs

      owner.stubs(:organization?).returns(true)
      owner.stubs(:renaming?).returns(false)
      owner.stubs(:can_create_repository?).with(actor, visibility: visibility).returns(true)

      GitHub.stubs(:public_repositories_available?).returns(true)

      orchestration.expects(:valid?).returns(true)
      orchestration.stubs(:execute)
      orchestration.expects(:failed?).returns(true)
      orchestration.expects(:error_message).returns("error_message")

      RepositoryOrchestration.expects(:clone_template).with(
        template_repository: template_repo,
        owner:,
        actor:,
        name:,
        copy_branches:,
        description:,
        visibility:,
        reflog_data:,
        current_integration_context: nil
      ).returns(orchestration)

      repo_clone, reason, message = template_repo.clone_template_to(owner,
        actor:,
        name:,
        copy_branches:,
        description:,
        visibility:,
        reflog_data:,
        current_integration_context: nil
      )

      assert_nil repo_clone
      assert_equal :unprocessable_entity, reason
      assert_equal "Could not clone: error_message", message
    end
  end

  private def build_clone_template_to_stubs
    owner = stub("owner", id: 1)
    actor = stub("actor", id: 2, flipper_id: "User:2")
    name = stub("name")
    copy_branches = stub("copy_branches")
    description = stub("description")
    visibility = stub("visibility")
    reflog_data = stub("reflog_data")
    orchestration = stub("orchestration")

    [
      owner,
      actor,
      name,
      copy_branches,
      description,
      visibility,
      reflog_data,
      orchestration
    ]
  end
end
