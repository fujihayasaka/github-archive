# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventReminderEventTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include HookEventTestHelper

  fixtures do
    @repo = create(:repository, :org_owned)
    @pull_request1 = create(:pull_request, :disable_disk_access, repository: @repo)
    @pull_request2 = create(:pull_request, :disable_disk_access, repository: @repo, head_ref: "topic2")
    @org = @repo.organization

    make_trusted_oauth_apps_owner
    @slack_integration = create(:slack_integration)
    @slack_installations = make_integration_installation(
      integration: @slack_integration,
      target: @org,
    )

    @actor = create(:user)
    @reminder = create(:reminder, remindable: @org, user: @actor)
    @personal_reminder = create(:personal_reminder, remindable: @org, slack_workspace: @reminder.slack_workspace)

    @repo_other_org = create(:repository, :org_owned)
    @pull_request_other_org = create(:pull_request, :disable_disk_access, repository: @repo_other_org)

    @other_repo = create(:repository, owner: @org)
    @pull_request_other_repo = create(:pull_request, :disable_disk_access, repository: @other_repo)
  end

  setup do

    @event_args = {
      action: "schedule",
      event_at: Time.zone.now,
      pull_request_ids: [@pull_request1.id, @pull_request2.id],
      repository_id: @repo.id,
    }
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::ReminderEvent, :action, :event_at, :reminder_id, :repository_id
  end

  test "#target_organization is the remindable for the reminder" do
    assert_equal @org, build_reminder_event.target_organization
    assert_equal @org, build_personal_reminder_event.target_organization
  end

  test "#target_repository is the looked up by repository_id for the organization" do
    assert_equal @repo, build_reminder_event.target_repository
    assert_equal @repo, build_personal_reminder_event.target_repository
  end

  test "reminder is found found by id" do
    assert_equal @reminder, build_reminder_event.reminder
    assert_equal @personal_reminder, build_personal_reminder_event.reminder
  end

  test "logs are emitted when a reminder event is queued" do
    expected_log = {
      "gh.webhook.event_type" => "",
      "gh.webhook.event_type_db" => "",
      "gh.scheduled_reminders.is_personal" => false,
      "gh.scheduled_reminders.pull_request_ids" => [@pull_request1.id, @pull_request2.id],
      "gh.scheduled_reminders.pull_request_ids_for_author" => [@pull_request1.id],
      "gh.scheduled_reminders.remindable.id" => @reminder.remindable_id,
      "gh.scheduled_reminders.remindable.login" => @reminder.remindable.login,
      "gh.scheduled_reminders.remindable.type" => @reminder.remindable_type,
      "gh.scheduled_reminders.reminder.id" => @reminder.id,
      "gh.scheduled_reminders.slack_workspace.id" => @reminder.slack_workspace.slack_id,
      "gh.scheduled_reminders.reminder_event_type" => "scheduled",
      "gh.repo.id" => @repo.id
    }
    assert_logged(**expected_log) do
      Hook::Event::ReminderEvent.queue(
        event_at: Time.zone.now,
        pull_request_ids: [@pull_request1.id, @pull_request2.id],
        pull_request_ids_for_author: [@pull_request1.id],
        reminder: @reminder,
        repository_id: @repo.id,
      )
    end
  end

  context "#pull_requests" do
    test "finds pull request by id" do
      assert_equal [@pull_request1, @pull_request2].to_set, build_reminder_event.pull_requests.to_set
      assert_equal [@pull_request1, @pull_request2].to_set, build_personal_reminder_event.pull_requests.to_set
    end

    test "scopes pull requests by repository" do
      reminder_event = build_reminder_event(pull_request_ids: [@pull_request1.id, @pull_request_other_org.id])
      assert_equal [@pull_request1], reminder_event.pull_requests

      personal_reminder_event = build_personal_reminder_event(pull_request_ids: [@pull_request1.id, @pull_request_other_repo.id])
      assert_equal [@pull_request1], personal_reminder_event.pull_requests
    end
  end

  context "#pull_requests_for_author" do
    test "finds pull request by id" do
      @event_args = {
        action: "schedule",
        event_at: Time.zone.now,
        pull_request_ids: [@pull_request2.id],
        pull_request_ids_for_author: [@pull_request1.id],
        repository_id: @repo.id,
      }

      assert_equal [@pull_request1].to_set, build_reminder_event.pull_requests_for_author.to_set
      assert_equal [@pull_request1].to_set, build_personal_reminder_event.pull_requests_for_author.to_set
    end
  end

  context "#reminder_event_context" do
    test "defaults to empty hash if no event_context is supplied" do
      assert_equal({}, build_reminder_event.reminder_event_context)
    end

    test "passes through reminder_event_context if one is supplied" do
      assert_equal({ "foo" => 1 }, build_reminder_event(reminder_event_context: { "foo" => 1 }).reminder_event_context)
    end

    test "converts reminder_event_context to indifferent access" do
      context = build_reminder_event(reminder_event_context: { "foo" => 1 }).reminder_event_context
      assert_equal 1, context[:foo]
      assert_equal 1, context["foo"]
    end
  end

  context "#deliverable?" do
    test "true if there is no actor_id" do
      assert build_reminder_event(actor_id: nil).deliverable?
      assert build_personal_reminder_event(actor_id: nil).deliverable?
    end

    test "true if there is an actor_id and the user can be found" do
      assert build_reminder_event(actor_id: @actor.id).deliverable?
      assert build_personal_reminder_event(actor_id: @actor.id).deliverable?
    end

    test "false if there is an actor_id but the user can't be found" do
      refute build_reminder_event(actor_id: -1).deliverable?
      refute build_personal_reminder_event(actor_id: -1).deliverable?
    end

    test "true if event_type is deleted" do
      assert build_reminder_event(event_type: Hook::Event::ReminderEvent::TYPE_DELETED).deliverable?
      assert build_personal_reminder_event(event_type: Hook::Event::ReminderEvent::TYPE_DELETED).deliverable?
    end

    test "target_repository returns nil and deliverable? returns false if reminder's organization and repository's organization don't match" do
      reminder_event = build_reminder_event(repository_id: @repo_other_org.id)
      personal_reminder_event = build_personal_reminder_event(repository_id: @repo_other_org.id)

      assert_nil reminder_event.target_repository
      assert_nil personal_reminder_event.target_repository

      refute reminder_event.deliverable?
      refute personal_reminder_event.deliverable?
    end

    test "pull_requests also returns empty array" do
      assert_equal [], build_reminder_event(repository_id: @repo_other_org.id).pull_requests
      assert_equal [], build_personal_reminder_event(repository_id: @repo_other_org.id).pull_requests
    end

    test "false when no prs are present" do
      event = build_reminder_event(pull_request_ids: [], pull_request_ids_for_author: [])
      refute event.deliverable?
    end

    test "false if pull_requests is empty" do
      refute build_reminder_event(pull_request_ids: []).deliverable?
      refute build_personal_reminder_event(pull_request_ids: []).deliverable?
    end
  end

  private

  def build_reminder_event(options = {})
    Hook::Event::ReminderEvent.new(@event_args.merge(
      reminder_id: @reminder.id, personal: false,
    ).merge(options))
  end

  def build_personal_reminder_event(options = {})
    Hook::Event::ReminderEvent.new(@event_args.merge(
      reminder_id: @personal_reminder.id, personal: true,
    ).merge(options))
  end
end
