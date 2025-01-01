# typed: true
# frozen_string_literal: true

require "test_helper"

class ArchivedProjectTest < GitHub::TestCase
  fixtures do
    @repo    = create(:repository)
    @project = create(:project, owner: @repo)
    @column  = create(:project_column, project: @project)
    @issue_card = create(:project_card, project: @project, column: @column)
    @note_card = create(:project_card, project: @project, column: @column, note: "Hello")

    @workflow = create(:project_workflow, project: @project)
    @workflow_action = create(:project_workflow_action, project_workflow: @workflow, project: @project)

    @org = create(:organization)
    @org_project = create(:project, owner: @org)
    @org_project_column = create(:project_column, project: @org_project)
    @org_project_issue_card = create(:project_card, project: @org_project, column: @org_project_column)
    @org_project_note_card = create(:project_card, project: @org_project, column: @org_project_column, note: "Hello")
  end

  test "is restored when a repository owner is restored" do
    only = [AddToSearchIndexJob]
    perform_enqueued_jobs(only: only) { @repo.remove(User.ghost, synchronous: true) }
    restore_repo(@repo)

    assert_predicate Project.where(id: @project.id), :exists?
    refute_predicate Archived::Project.where(id: @project.id), :exists?
  end

  test "is deleted (not archived) when an org owner is removed" do
    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { @org.destroy }

    assert_raises(ActiveRecord::RecordNotFound) do
      @org_project.reload
    end
    refute_predicate Archived::Project.where(id: @org_project.id), :exists?
    refute_predicate Archived::ProjectColumn.where(id: @org_project_column.id), :exists?
    refute_predicate Archived::ProjectCard.where(id: @org_project_issue_card.id), :exists?
    refute_predicate Archived::ProjectCard.where(id: @org_project_note_card.id), :exists?
  end

  test "columns are archived/restored" do
    only = [DestroyDependentRecordsJob, RepositoryOrchestrationJob]
    perform_enqueued_jobs(only: only) { @repo.remove(@repo.owner) }
    assert_archived @column, "repo"
    restore_repo(@repo)
    assert_restored @column, "repo"
  end

  context "card archival/restoration" do
    test "works for cards in repo-owned projects" do
      only = [DestroyDependentRecordsJob, RepositoryOrchestrationJob]
      perform_enqueued_jobs(only: only) { @repo.remove(@repo.owner) }
      assert_archived @issue_card, "repo"
      assert_archived @note_card, "repo"

      restore_repo(@repo)
      assert_restored @issue_card, "repo"
      assert_restored @note_card, "repo"
    end

    test "works for cards in org-owned projects, when the card content's repo is deleted" do
      repo = @org_project_issue_card.content.repository

      only = [DestroyDependentRecordsJob, RepositoryOrchestrationJob]
      perform_enqueued_jobs(only: only) { repo.remove(@org.admin) }
      assert_archived @org_project_issue_card, "repo"
      assert_predicate ProjectCard.where(id: @org_project_note_card.id), :exists?

      restore_repo(repo)
      assert_restored @org_project_issue_card, "repo"
      assert_predicate ProjectCard.where(id: @org_project_note_card.id), :exists?
    end

    context "when project is directly deleted" do
      test "works for cards in repo-owned projects" do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { Archived::Project.archive(@project) }
        assert_archived @issue_card, "project"
        assert_archived @note_card, "project"

        Archived::Project.find(@project.id).restore
        assert_restored @issue_card, "project"
        assert_restored @note_card, "project"
      end

      test "works for cards in org-owned projects" do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { Archived::Project.archive(@org_project) }
        assert_archived @org_project_issue_card, "project"
        assert_archived @org_project_note_card, "project"

        Archived::Project.find(@org_project.id).restore
        assert_restored @org_project_issue_card, "project"
        assert_restored @org_project_note_card, "project"
      end
    end
  end

  context "workflows" do
    test "workflows are archived/restored when a repo is deleted" do
      only = [DestroyDependentRecordsJob, RepositoryOrchestrationJob]
      perform_enqueued_jobs(only: only) { @repo.remove(@repo.owner) }
      assert_archived @workflow, "repo"

      restore_repo(@repo)
      assert_restored @workflow, "repo"
    end

    test "workflows are archived/restored when a project is archived" do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { Archived::Project.archive(@project) }
      assert_archived @workflow, "project"

      Archived::Project.find(@project.id).restore
      assert_restored @workflow, "project"
    end

    test "workflow actions are archived/restored when a repo is deleted" do
      only = [DestroyDependentRecordsJob, RepositoryOrchestrationJob]
      perform_enqueued_jobs(only: only) { @repo.remove(@repo.owner) }
      assert_archived @workflow_action, "repo"

      restore_repo(@repo)
      assert_restored @workflow_action, "repo"
    end

    test "workflow actions are archived/restored when a project is archived" do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { Archived::Project.archive(@project) }
      assert_archived @workflow_action, "project"

      Archived::Project.find(@project.id).restore
      assert_restored @workflow_action, "project"
    end
  end

  test "archiving a project keeps special names/bodies intact" do
    string_containing_emoji = "This project is great! #{GRIN_EMOJI * 5}"

    project = create(:project, name: "[name] #{string_containing_emoji}",
                           body: "[body] #{string_containing_emoji}")

    only = [ClearAbilitiesJob]
    archived_project = perform_enqueued_jobs(only: only) { Archived::Project.archive(project) }

    assert_equal "[name] #{string_containing_emoji}", archived_project.name
    assert_equal "[body] #{string_containing_emoji}", archived_project.body
  end

  def restore_repo(repo)
    GitRPC::Client.any_instance.stubs(:gitbackups_restore).with do |spec|
      GitHub::GitbackupsTestHelper.restore_from_example(spec)
    end
    Repository.restore(repo.id)
  end

  def assert_archived(resource, initiator)
    if initiator == "repo"
      # we don't archive repos
      return
    end
    id = resource.id
    klass = resource.class
    archived_klass = "Archived::#{klass.name}".constantize
    assert_predicate archived_klass.where(id: id), :exists?, "#{archived_klass.name} was not created when #{initiator} was archived."
    refute_predicate klass.where(id: id), :exists?, "#{klass.name} was not removed when #{initiator} was archived."
  end

  def assert_restored(resource, initiator)
    id = resource.id
    klass = resource.class
    archived_klass = "Archived::#{klass.name}".constantize
    assert_predicate klass.where(id: id), :exists?, "#{klass.name} was not restored when #{initiator} was restored."
    refute_predicate archived_klass.where(id: id), :exists?, "#{archived_klass.name} was not removed when #{initiator} was restored."
  end
end
