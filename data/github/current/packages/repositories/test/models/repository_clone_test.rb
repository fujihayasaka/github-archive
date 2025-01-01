# typed: strict
# frozen_string_literal: true

require "test_helper"

class RepositoryCloneModelTest < GitHub::TestCase
  include HydroTestHelpers
  include BackgroundDeletesTestHelpers

  context "Hydro events" do
    test "logs event on creation", skip_enterprise: true do
      clone_repo = create(:repository)
      template_repo = create(:repository, template: true)
      cloner = create(:user)
      message = {
        user: Hydro::EntitySerializer.user(cloner),
        template_repository: Hydro::EntitySerializer.repository(template_repo),
        clone_repository: Hydro::EntitySerializer.repository(clone_repo),
      }

      create(:repository_clone, clone_repository: clone_repo, template_repository: template_repo,
             cloning_user: cloner)

      assert_hydro_published(message, schema: "github.v1.RepositoryCloneCreate")
    end
  end

  context "validations" do
    test "requires a cloning user" do
      repo_clone = RepositoryClone.new
      refute_predicate repo_clone, :valid?
      assert_includes repo_clone.errors[:cloning_user], "can't be blank"
    end

    test "requires a template repository" do
      repo_clone = RepositoryClone.new
      refute_predicate repo_clone, :valid?
      assert_includes repo_clone.errors[:template_repository], "can't be blank"
    end

    test "requires an active template repository" do
      template_repo = create(:repository, template: true, active: nil)
      repo_clone = RepositoryClone.new(template_repository: template_repo)
      refute_predicate repo_clone, :valid?
      assert_includes repo_clone.errors[:template_repository], "must be active"
    end

    test "requires template repository to be marked as a template" do
      repo = create(:repository, template: false)
      repo_clone = RepositoryClone.new(template_repository: repo)
      refute_predicate repo_clone, :valid?
      assert_includes repo_clone.errors[:template_repository], "must be marked as a template"
    end

    test "requires a clone repository" do
      repo_clone = RepositoryClone.new
      refute_predicate repo_clone, :valid?
      assert_includes repo_clone.errors[:clone_repository], "can't be blank"
    end

    test "requires a unique clone repository" do
      repo_clone = create(:repository_clone)
      repo_clone2 = RepositoryClone.new(clone_repository: repo_clone.clone_repository)
      refute_predicate repo_clone2, :valid?
      assert_includes repo_clone2.errors[:clone_repository_id], "has already been taken"
    end

    test "requires cloning user to have read access to the clone repository" do
      user = create(:user)
      clone_repo = create(:private_repository)
      repo_clone = build(:repository_clone, cloning_user: user, clone_repository: clone_repo)
      refute_predicate repo_clone, :valid?
      assert_includes repo_clone.errors[:cloning_user],
        "does not have permission to view the clone repository"
    end

    test "properly hydrate installation when cloning user is a bot" do
      org = create(:organization)
      installation = make_integration_installation(target: org, permissions: { "administration" => :write, "contents" => :write, "metadata" => :read })
      user = User.find(installation.bot.id)

      clone_repo = create(:private_repository, owner: org)
      repo_clone = build(:repository_clone, cloning_user: user, clone_repository: clone_repo)
      assert_predicate repo_clone, :valid?
      refute_includes repo_clone.errors[:cloning_user],
        "does not have permission to view the clone repository"
    end
  end

  context "#error?" do
    test "true when repo clone is in the 'error' state" do
      repo_clone = build(:repository_clone, state: :error)
      assert_predicate repo_clone, :error?
    end

    test "false when repo clone is not in the 'error' state" do
      repo_clone = build(:repository_clone, state: :finished)
      refute_predicate repo_clone, :error?
    end
  end

  context "#cloning?" do
    test "true when repo clone is in the 'cloning' state" do
      repo_clone = build(:repository_clone, state: :cloning)
      assert_predicate repo_clone, :cloning?
    end

    test "false when repo clone is not in the 'cloning' state" do
      repo_clone = build(:repository_clone, state: :finished)
      refute_predicate repo_clone, :cloning?
    end
  end

  context "#finished?" do
    test "true when repo clone is in the 'finished' state" do
      repo_clone = build(:repository_clone, state: :finished)
      assert_predicate repo_clone, :finished?
    end

    test "false when repo clone is not in the 'finished' state" do
      repo_clone = build(:repository_clone, state: :error)
      refute_predicate repo_clone, :finished?
    end
  end

  context "for_clone_repo scope" do
    test "filters results based on the repository that was created as a clone" do
      repo = create(:repository)
      repo_clone1 = create(:repository_clone, clone_repository: repo)
      repo_clone2 = create(:repository_clone)

      result = RepositoryClone.for_clone_repo(repo)

      assert_includes result, repo_clone1
      refute_includes result, repo_clone2
    end
  end

  context "cloning scope" do
    test "only includes those clones that are still in progress" do
      repo_clone1 = create(:repository_clone, :finished)
      repo_clone2 = create(:repository_clone)

      result = RepositoryClone.cloning

      refute_includes result, repo_clone1
      assert_includes result, repo_clone2
    end
  end

  context "finished scope" do
    test "only includes those clones that have finished" do
      repo_clone1 = create(:repository_clone, :finished)
      repo_clone2 = create(:repository_clone)

      result = RepositoryClone.finished

      assert_includes result, repo_clone1
      refute_includes result, repo_clone2
    end
  end

  test "is deleted with repository" do
    repo_clone = create(:repository_clone)
    other_repo_clone = create(:repository_clone)

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = repo_clone.template_repository
      config.expect_destroyed = [repo_clone]
      config.expect_not_destroyed = [other_repo_clone]
    end
  end
end
