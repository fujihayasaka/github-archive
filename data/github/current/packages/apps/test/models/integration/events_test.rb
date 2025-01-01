# typed: true
# frozen_string_literal: true

require "test_helper"

class Integration::EventsTest < GitHub::TestCase
  SUPPORTED_DOTCOM_ONLY_EVENTS = %w(
    org_block
    repository_advisory
    sub_issues
  )

  SUPPORTED_EVENTS = %w(
    branch_protection_configuration
    branch_protection_rule
    code_scanning_alert
    check_run
    check_suite
    commit_comment
    create
    custom_property
    custom_property_values
    discussion
    discussion_comment
    delete
    dependabot_alert
    deploy_key
    deployment
    deployment_protection_rule
    deployment_review
    deployment_status
    exemption_request_push_ruleset
    exemption_request_secret_scanning
    fork
    gollum
    issue_comment
    issues
    installation_target
    label
    milestone
    member
    membership
    merge_group
    merge_queue_entry
    meta
    organization
    page_build
    personal_access_token_request
    project
    project_card
    project_column
    projects_v2_item
    projects_v2
    projects_v2_status_update
    public
    pull_request
    pull_request_review
    pull_request_review_comment
    pull_request_review_thread
    push
    registry_package
    release
    reminder
    repository
    repository_dispatch
    repository_ruleset
    security_and_analysis
    secret_scanning_alert
    secret_scanning_alert_location
    star
    status
    team
    team_add
    watch
    workflow_dispatch
    workflow_job
    workflow_run
  )

  RESOURCE_TO_EVENTS = {
    "actions"                     => %w(workflow_job workflow_run),
    "issues"                      => %w(issue_comment issues milestone sub_issues),
    "pull_requests"               => %w(milestone pull_request pull_request_review pull_request_review_comment pull_request_review_thread reminder merge_queue_entry),
    "discussions"                 => %w(discussion discussion_comment),
    "statuses"                    => %w(status),
    "checks"                      => %w(check_suite check_run),
    "deployments"                 => %w(deployment deploy_key deployment_protection_rule deployment_status deployment_review),
    "administration"              => %w(branch_protection_configuration branch_protection_rule repository_ruleset exemption_request_push_ruleset member security_and_analysis),
    "contents"                    => %w(commit_comment create delete fork gollum push release repository_dispatch workflow_dispatch workflow_job workflow_run),
    "metadata"                    => %w(label public repository watch star),
    "merge_queues"                => %w(merge_group),
    "members"                     => %w(member membership organization team team_add),
    "repository_projects"         => %w(project_card project_column project),
    "organization_projects"       => %w(project_card project_column project projects_v2_item projects_v2 projects_v2_status_update),
    "organization_personal_access_token_requests" => %w(personal_access_token_request),
    "pages"                       => %w(page_build),
    "organization_administration" => %w(org_block repository_ruleset),
    "organization_custom_properties" => %w(custom_property custom_property_values),
    "packages"                    => %w(registry_package),
    "repository_advisories"       => %w(repository_advisory),
    "security_events"             => %w(code_scanning_alert),
    "secret_scanning_alerts"      => %w(secret_scanning_alert secret_scanning_alert_location exemption_request_secret_scanning),
    "vulnerability_alerts"        => %w(dependabot_alert),
  }.freeze

  fixtures do
    @actor = create(:user)
    @integration = create :integration
    @slack_app = create :slack_integration
    @msteams_app = create :msteams_integration
    @added_feature_flags = []
  end

  teardown do
    reset_feature_flags!
  end

  test "supported events", skip_enterprise: true do
    assert_same_elements (SUPPORTED_EVENTS + SUPPORTED_DOTCOM_ONLY_EVENTS), ::Integration::Events::SUPPORTED_EVENTS
  end

  test "supported events in Enterprise", enterprise_only: true do
    assert_same_elements SUPPORTED_EVENTS, ::Integration::Events::SUPPORTED_EVENTS
  end

  test "events for resources" do
    assert_same_elements Integration::Events::RESOURCE_TO_EVENTS.keys, RESOURCE_TO_EVENTS.keys

    Integration::Events::RESOURCE_TO_EVENTS.each do |resource, events|
      assert_equal RESOURCE_TO_EVENTS[resource], events
    end
  end

  test ".event_types_to_resources does not return feature flagged events" do
    add_feature_flag(:issue_comment, :my_test_feature, enabled: false)
    refute Integration::Events.event_types_to_resources["issue_comment"]
  end

  test ".event_types_to_resources does not return internal events" do
    refute Integration::Events.event_types_to_resources["reminder"]
  end

  test ".event_types_to_resources returns internal events for enabled integrations" do
    assert Integration::Events.event_types_to_resources(integration: @slack_app)["reminder"]
    assert Integration::Events.event_types_to_resources(integration: @msteams_app)["reminder"]
  end

  test ".event_types_for_resource returns an empty array for an unknown event type" do
    assert_empty(
      Integration::Events.event_types_for_resource("fake_resource", actor: @actor),
    )
  end

  test ".event_types_for_resource returns an array of events for a valid resource" do
    assert_equal(
      RESOURCE_TO_EVENTS["metadata"],
      Integration::Events.event_types_for_resource("metadata", actor: @actor),
    )
  end

  test ".event_types_for_resource does not return feature flagged events" do
    add_feature_flag(:issue_comment, :my_test_feature, enabled: true)
    assert_equal(
      RESOURCE_TO_EVENTS["issues"] - %w(issue_comment),
      Integration::Events.event_types_for_resource("issues"),
    )
  end


  test ".event_types_for_resource includes feature flagged events when asked" do
    add_feature_flag(:issue_comment, :my_test_feature, enabled: false)
    assert_equal(
      RESOURCE_TO_EVENTS["issues"],
      Integration::Events.event_types_for_resource(
        "issues",
        include_all_events: true,
      ),
    )
  end

  test ".event_types_for_resource includes feature flagged events and internal events when asked" do
    add_feature_flag(:issue_comment, :my_test_feature, enabled: false)
    assert_equal(
      RESOURCE_TO_EVENTS["pull_requests"],
      Integration::Events.event_types_for_resource(
        "pull_requests",
        include_all_events: true,
      ),
    )
  end

  test ".event_types_for_resource does not return disabled feature flagged events" do
    add_feature_flag(:issue_comment, :my_test_feature, enabled: false)
    assert_equal(
      RESOURCE_TO_EVENTS["issues"] - %w(issue_comment),
      Integration::Events.event_types_for_resource("issues", actor: @actor),
    )
  end

  test ".event_types_for_resource does not return intenal events if integration does not have access" do
    assert_equal(
      RESOURCE_TO_EVENTS["pull_requests"] - %w(reminder),
      Integration::Events.event_types_for_resource("pull_requests", actor: @actor, integration: @integration),
    )
  end

  test ".event_types_for_resource supports multiple events" do
    add_feature_flag(:issue_comment, :my_test_feature, enabled: false)
    add_feature_flag(:issues,        :my_test_feature, enabled: false)
    assert_equal(
      RESOURCE_TO_EVENTS["issues"] - %w(issue_comment issues),
      Integration::Events.event_types_for_resource("issues", actor: @actor),
    )
  end

  test ".event_types_for_resource supports multiple flags" do
    add_feature_flag(:issue_comment, :my_test_feature, enabled: false)
    add_feature_flag(:check_suite,   :check_suite_flag, enabled: true)
    assert_equal(
      RESOURCE_TO_EVENTS["issues"] - %w(issue_comment),
      Integration::Events.event_types_for_resource("issues", actor: @actor),
    )
    assert_equal(
      RESOURCE_TO_EVENTS["checks"],
      Integration::Events.event_types_for_resource("checks", actor: @actor),
    )
  end

  test ".event_types_for_resource supports multiple flags [pull_requests]" do
    add_feature_flag(:pull_request, :my_test_feature, enabled: false)
    add_feature_flag(:check_suite,   :check_suite_flag, enabled: true)
    assert_equal(
      RESOURCE_TO_EVENTS["pull_requests"] - %w(pull_request reminder),
      Integration::Events.event_types_for_resource("pull_requests", actor: @actor),
    )
    assert_equal(
      RESOURCE_TO_EVENTS["checks"],
      Integration::Events.event_types_for_resource("checks", actor: @actor),
    )
  end

  test ".event_types_for_resource supports multiple flags with one flag enabled" do
    add_feature_flag(:issue_comment, :my_test_feature,  enabled: false)
    add_feature_flag(:issue_comment, :my_test_feature2, enabled: true)
    assert_equal(
      RESOURCE_TO_EVENTS["issues"],
      Integration::Events.event_types_for_resource("issues", actor: @actor),
    )
  end

  test ".event_types_for_resource does returns enabled feature flagged events" do
    add_feature_flag(:issue_comment, :my_test_feature, enabled: true)
    assert_equal(
      RESOURCE_TO_EVENTS["issues"],
      Integration::Events.event_types_for_resource("issues", actor: @actor),
    )
  end

  test ".event_types_for_resource does returns internal events for integration that have access" do
    assert_equal(
      RESOURCE_TO_EVENTS["pull_requests"],
      Integration::Events.event_types_for_resource("pull_requests", integration: @slack_app),
    )
    assert_equal(
      RESOURCE_TO_EVENTS["pull_requests"],
      Integration::Events.event_types_for_resource("pull_requests", actor: @actor, integration: @msteams_app),
    )
  end

  test ".hook_event_for_event_type returns a hook event" do
    assert_equal Hook::Event::IssuesEvent, Integration::Events.hook_event_for_event_type("issues")
  end

  test ".hook_event_for_event_type returns pull request hook event" do
    assert_equal Hook::Event::PullRequestEvent, Integration::Events.hook_event_for_event_type("pull_request")
  end

  test ".hook_event_for_event_type returns reminder hook event" do
    assert_equal Hook::Event::ReminderEvent, Integration::Events.hook_event_for_event_type("reminder")
  end

  test ".organization_event? returns true for a valid event" do
    assert Integration::Events.organization_event?("membership"), "not a valid event"
  end

  test ".repository_event? returns true for a valid event" do
    assert Integration::Events.repository_event?("fork"), "not a valid event"
  end

  test ".resources_for_event returns the resource required for an event" do
    assert_equal %w(members), Integration::Events.resources_for_event("organization")
    assert_equal %w(issues pull_requests), Integration::Events.resources_for_event("milestone")
    assert_equal %w(organization_projects repository_projects), Integration::Events.resources_for_event("project_card")
  end

  test ".repository_resources_for_event returns the resource required for an event" do
    assert_equal %w(), Integration::Events.repository_resources_for_event("organization")
    assert_equal %w(issues pull_requests), Integration::Events.repository_resources_for_event("milestone")
    assert_equal %w(repository_projects), Integration::Events.repository_resources_for_event("project_card")
  end

  test ".organization_resources_for_event returns the resource required for an event" do
    assert_equal %w(members), Integration::Events.organization_resources_for_event("organization")
    assert_equal %w(), Integration::Events.organization_resources_for_event("milestone")
    assert_equal %w(organization_projects), Integration::Events.organization_resources_for_event("project_card")
  end

  private

  def add_feature_flag(event, flag, enabled:)
    original_flag_state = GitHub.flipper[flag].state
    GitHub.flipper[flag].disable
    Integration::Events.feature_flag(event, flag)
    set_flag_state_for_actor(flag, enabled)
    @added_feature_flags.push([event, flag, original_flag_state])
  end

  def reset_feature_flags!
    @added_feature_flags.each do |event, flag, original_flag_state|
      Integration::Events.remove_feature_flag(event, flag)
      set_flag_global_state(flag, (original_flag_state != :on))
    end
  end

  def set_flag_state_for_actor(flag, should_enable)
    if should_enable
      GitHub.flipper[flag].enable_actor(@actor)
    else
      GitHub.flipper[flag].disable_actor(@actor)
    end
  end

  def set_flag_global_state(flag, should_enable)
    if should_enable
      GitHub.flipper[flag].enable
    else
      GitHub.flipper[flag].disable
    end
  end
end
