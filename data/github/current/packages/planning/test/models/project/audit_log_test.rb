# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectAuditLogTest < GitHub::TestCase
  include AuditLogHelpers
  include GitHub::PullRequestTestHelpers
  include PlatformTestHelpers::InterfaceHelpers
  include ProjectCardHelpers

  fixtures do
    @owner = create(:user)

    @org = create(:organization, plan: "silver").tap do |o|
      o.add_member(@owner, action: :admin)
    end

    @repo = create(:repository, owner: @org)
    @project = create(:project, owner: @repo)
    @column = create(:project_column, project: @project, purpose: "todo")
  end


  context "#column_name" do
    test "nil for project events" do
      with_es_refresh do
        @project.update_attribute(:name, "number one project")
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        assert_nil entry.column_name
      end
    end

    test "present for card and column events" do
      with_es_refresh do
        create(:project_card, column: @column)
        @column.update_attribute(:name, "number one column")
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        refute_nil entry.column_name
      end
    end
  end

  context "#previous_column_name" do
    test "nil for project and column events" do
      with_es_refresh do
        @project.update_attribute(:name, "number two project")
        @column.update_attribute(:name, "number two column")
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        assert_nil entry.previous_column_name
      end
    end

    test "present for card move events" do
      with_es_refresh do
        card = create(:project_card, column: @column)
        @column.prioritize_card!(card)
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        if entry.event_type == "move"
          refute_nil entry.previous_column_name
        else
          assert_nil entry.previous_column_name
        end
      end
    end
  end

  context "#column_purpose and #old_column_purpose" do
    test "nil for project and column rename events" do
      with_es_refresh do
        @project.update_attribute(:name, "number three project")
        @column.update_attribute(:name, "number three column")
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        assert_nil entry.column_purpose
        assert_nil entry.old_column_purpose
      end
    end

    test "present when column purpose changes" do
      with_es_refresh do
        @column.update_attribute(:purpose, "done")
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        refute_nil entry.column_purpose
        refute_nil entry.old_column_purpose
      end
    end

    test "not present when column purpose changes and feature flag is off" do
      with_es_refresh do
        @column.update_attribute(:purpose, "done")
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        refute_nil entry.column_purpose
      end
    end
  end

  context "card entry present" do
    test "present when inserting card at the top" do
      with_es_refresh do
        ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Yup" })
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        refute_nil entry.column_name
      end
    end

    test "present when inserting card after another card" do
      existing_card = create(:project_card, column: @column)
      with_es_refresh do
        ProjectCard.create_in_column(@column, creator: @owner, after: existing_card, content_params: { content_type: "Note", note: "Yup" })
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        refute_nil entry.column_name
      end
    end
  end

  context "#active_card?" do

    test "card deleted from project" do
      with_es_refresh do
        card = create(:project_card, column: @column)
        card.destroy
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        refute_predicate entry, :active_card?
      end
    end

    test "column deleted from project removes card" do
      with_es_refresh do
        create(:project_card, column: @column)
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { @column.destroy }
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        if entry.event_namespace == "project_card"
          refute_predicate entry, :active_card?
        end
      end
    end
  end

  context "card_converted_to_issue_with_title_change?" do
    test "card converted with no title change" do
      with_es_refresh do
        card = create(:project_card, column: @column, note: "get butter")
        convert_note_to_issue(card: card, converter: @owner, repository: @repo, title: "get butter")
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        refute_predicate entry, :card_converted_to_issue_with_title_change?
      end
    end

    test "addition of note that was converted to redacted card should be redacted too" do
      repo = create(:private_repository, owner: @owner)
      project = create(:user_project, owner: @owner)
      column = create(:project_column, project: project, purpose: "todo")
      with_es_refresh do
        card = create(:project_card, column: column, note: "get butter")
        convert_note_to_issue(card: card, converter: @owner, repository: repo, title: "get butter")
      end

      audit_log = Project::AuditLog.new(project, viewer: create(:user))
      refute_empty audit_log

      audit_log.each do |entry|
        assert_predicate entry, :card_redacted? if entry.action == "project_card.create"
      end
    end

    test "card converted with no title change, but should be redacted" do
      repo = create(:private_repository, owner: @owner)
      project = create(:user_project, owner: @owner)
      column = create(:project_column, project: project, purpose: "todo")
      with_es_refresh do
        card = create(:project_card, column: column, note: "get butter")
        convert_note_to_issue(card: card, converter: @owner, repository: repo, title: "get butter")
      end

      audit_log = Project::AuditLog.new(project, viewer: create(:user))
      refute_empty audit_log

      audit_log.each do |entry|
        assert_predicate entry, :card_redacted? if entry.event_type == "convert"
      end
    end

    test "card converted and title changed" do
      with_es_refresh do
        card = create(:project_card, column: @column, note: "get butter")
        convert_note_to_issue(card: card, converter: @owner, repository: @repo, title: "get lard")
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        if entry.event_type == "convert"
          assert_predicate entry, :card_converted_to_issue_with_title_change?
        end
      end
    end
  end

  context "#card_title" do
    test "card with no content" do
      note = "get 5 eggs"
      with_es_refresh do
        create(:project_card, column: @column, note: note)
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        assert_equal note, entry.card_title
      end
    end

    test "card with issue content" do
      issue = create(:issue, repository: @repo, title: "3 eggs were cracked")

      with_es_refresh do
        create(:project_card, column: @column, content: issue)
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        assert_equal issue.title, entry.card_title
      end
    end
  end

  context "automation" do
    test "card with content moved without automation" do
      issue = create(:issue, repository: @repo, title: "3 eggs were cracked")

      card = create(:pending_project_card, project: @project, content: issue, creator: @owner)

      with_es_refresh do
        @column.prioritize_card!(card)
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        assert_equal issue.title, entry.card_title
        refute_predicate entry, :automated?
      end
    end

    test "card with content moved via automation" do
      issue = create(:issue, repository: @repo, title: "3 eggs were cracked")

      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::PR_REOPENED_TRIGGER, project: @project)
      workflow.set_transition_action(column: @column, creator: @owner)

      with_es_refresh do
        create(:pending_project_card, project: @project, content: issue, creator: @owner)
      end

      audit_log = Project::AuditLog.new(@project, viewer: @owner)
      refute_empty audit_log

      audit_log.each do |entry|
        if entry.event_namespace == "project_card"
          assert_equal issue.title, entry.card_title
          assert_equal "created", entry.past_tense_event_type
          assert_predicate entry, :automated?
          assert_equal workflow.trigger_type, entry.automation_trigger
          assert_equal ProjectWorkflowAction::TRANSITION_TO_COLUMN, entry.automation_action
          assert_equal "Pull Request reopened", entry.workflow_type
        end
      end
    end

    test "card moved via pending approval trigger has review dismisser as actor" do
      pull = make_pr_and_repos
      owner = @make_pr_repo_owner
      project = create(:project, owner: pull.repository)
      column = create(:project_column, project: project)
      review_column = create(:project_column, project: project, purpose: "in_progress")
      reviewer = create(:user)

      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::PR_PENDING_APPROVAL_TRIGGER, project: project)
      workflow.set_transition_action(column: review_column, creator: owner)

      review = pull.reviews.create!(user: reviewer, head_sha: pull.head_sha, body: "bad code")
      review.approve!
      card = create(:project_card, column: column, content: pull.issue, creator: owner)

      dismisser = pull.user

      with_es_refresh do
        perform_enqueued_jobs(only: [ProcessProjectWorkflowsJob]) do
          review.dismiss!(dismisser, message: "no thanks")
        end
      end

      assert_equal review_column.id, card.reload.column.id

      audit_log = Project::AuditLog.new(project, viewer: owner).select do |entry|
        entry.action == "project_card.move"
      end
      refute_empty audit_log

      audit_log.each do |entry|
        assert_equal dismisser, entry.actor
      end
    end
  end

  context "redacted cards" do
    test "viewer doesn't have permission to view card" do
      private_repo = create(:private_repository, owner: @org)
      private_issue = create(:issue, repository: private_repo)

      with_es_refresh do
        create(:project_card, column: @column, content: private_issue)
      end

      viewer = create(:user)
      audit_log = Project::AuditLog.new(@project, viewer: viewer)
      refute_empty audit_log

      audit_log.each do |entry|
        assert_predicate entry, :card_redacted?
        assert_nil entry.card_title
        assert_equal ProjectCardRedactor::RedactedCard::INSUFFICIENT_PERMISSION, entry.card_redacted_reason
      end
    end

    test "card has content that is spammy to viewer" do
      spammer = create(:user, login: "spammer", spammy: true)
      spammy_issue = create(:issue, repository: @repo, user: spammer, title: "DEALS DEALS DEALS")
      with_es_refresh do
        create(:project_card, column: @column, content: spammy_issue)
      end

      viewer = create(:user)
      audit_log = Project::AuditLog.new(@project, viewer: viewer)
      refute_empty audit_log

      audit_log.each do |entry|
        assert_predicate entry, :card_redacted?
        assert_nil entry.card_title
        assert_equal ProjectCardRedactor::RedactedCard::SPAMMY_CONTENT, entry.card_redacted_reason
      end
    end unless GitHub.enterprise?

    test "card has content that was a deleted issue but can't see" do
      private_repo = create(:private_repository, owner: @org)
      private_issue = create(:issue, repository: private_repo)

      with_es_refresh do
        create(:project_card, column: @column, content: private_issue)
      end

      viewer = create(:user)
      audit_log = Project::AuditLog.new(@project, viewer: viewer)
      refute_empty audit_log

      DeletedIssue.delete_issue(private_issue, deleter: @owner)

      audit_log.each do |entry|
        assert_predicate entry, :card_redacted?
        assert_nil entry.card_title
        assert_equal ProjectCardRedactor::RedactedCard::INSUFFICIENT_PERMISSION, entry.card_redacted_reason
      end
    end

    test "card has content that was a deleted issue" do
      issue = create(:issue, repository: @repo, user: @repo.owner, title: "DEALS DEALS DEALS")
      with_es_refresh do
        create(:project_card, column: @column, content: issue)
      end
      DeletedIssue.delete_issue(issue, deleter: @repo.owner)

      viewer = create(:user)
      audit_log = Project::AuditLog.new(@project, viewer: viewer)
      refute_empty audit_log

      audit_log.each do |entry|
        assert_predicate entry, :card_redacted?
        assert_nil entry.card_title
        assert_equal ProjectCardRedactor::RedactedCard::ISSUE_MISSING, entry.card_redacted_reason
      end
    end
  end

  context "collaboration settings changes" do
    test "are excluded" do
      org_project = create(:project, owner: @org)

      with_es_refresh do
        org_project.update_org_permission(:read)
      end

      audit_log = Project::AuditLog.new(org_project, viewer: @org.admins.first)

      audit_log.each do |entry|
        refute_equal "project.update_org_permission", entry.action
      end
    end
  end
end
