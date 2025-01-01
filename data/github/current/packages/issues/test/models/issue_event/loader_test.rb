# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"
require "test_helpers/issue_event_test_helper"
require "test_helpers/query_identifier_helper"

class LoaderTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include IssueEventTestHelper
  include GitHub::PullRequestTestHelpers
  include QueryIdentifierHelper

  setup do
    @selected_attributes = [:issue_id, :id, :created_at, :event, :commit_id, :actor_id, :repository_id, :commit_repository_id]
    @visible_events_only = true
    @exclude_event_types = []
    @requested_events = ::IssueEvent::VALID_EVENTS
  end

  def compare_queries(expected_queries, actual_queries)
    assert_equal parse_queries(expected_queries), identify_queries(actual_queries)
  end

  context "load" do

    test "with a bunch of events" do
      creator = create(:user)
      viewer = create(:user)
      repo = create(:repository, owner: creator, from_example: :simple)
      issue = create(:issue, repository: repo, user: viewer)

      create_label_events(creator, repo, issue)
      create_milestone_events(creator, repo, issue)
      create_referenced_events(creator, repo, issue)
      create_cross_reference_events(creator, repo, issue)
      create_invisible_events(creator, issue)
      create_project_events(creator, repo, issue)

      events = IssueEvent::Loader.new(viewer,
        base_scope: IssueEvent.where(issue_id: [issue.id]),
        selected_attributes: @selected_attributes,
        visible_events_only: @visible_events_only,
        exclude_event_types: @exclude_event_types,
        requested_events: @requested_events
      ).load

      assert_equal events.count, 12
      assert_equal events.first[:event], "labeled"
    end

    context "label events" do
      test "without label_id AND without label_name are ignored" do
        creator = create(:user)
        other_user = create(:user)
        viewer = create(:user)
        repo = create(:repository, owner: creator)
        issue = create(:issue, repository: repo, user: viewer)
        label = create(:label, name: "bug label", repository: repo)

        create(:issue_event, event: "labeled", issue: issue, actor: other_user, label_id: label.id)
        create(:issue_event, event: "labeled", issue: issue, actor: other_user, label_name: label.name)
        create(:issue_event, event: "labeled", issue: issue, actor: other_user, label: label)
        create(:issue_event, event: "labeled", issue: issue, actor: other_user) # should be ignored

        events = IssueEvent::Loader.new(viewer,
          base_scope: IssueEvent.where(issue_id: [issue.id]),
          selected_attributes: @selected_attributes,
          visible_events_only: @visible_events_only,
          exclude_event_types: @exclude_event_types,
          requested_events: @requested_events
        ).load

        assert_equal events.count, 3
      end
    end

    context "experiment loader" do
      test "parse and serialize raw_data with no failures" do
        creator = create(:user)
        repo = create(:repository, owner: creator)
        issue = create(:issue, repository: repo, user: creator)
        label = create(:label, repository: repo, name: "label", color: "d73a4a")
        event = IssueEvent.create!(issue: issue, actor: creator, event: "labeled")

        raw_data = {
          label_id: label.id,
          label_name: label.name,
          label_color: label.color,
        }
        encoded = Coders::Handler.new(Coders::IssueEventCoder, compressor: GitHub::ZPack).dump(raw_data)

        # Inspired from packages/issues/test/models/issue_transfer_test.rb
        # Manually simulate existing production serialized attributes inside
        # the IssueEvent model by inserting raw_data
        IssueEvent.where(id: event.id).update_all(raw_data: encoded)

        # Delete the issue_event_details row to simulate pre-transition production
        # where only the serialized attributes from the issue event model exist
        event.issue_event_detail.delete
        event.reload
        event.issue_event_detail.save
        issue.reload

        refute_error_reported do
          IssueEvent::Loader.new(creator,
            base_scope: ::IssueEvent.unscoped.where(issue_id: [issue.id], repository_id: [repo.id]),
            selected_attributes: @selected_attributes,
            visible_events_only: @visible_events_only,
            exclude_event_types: @exclude_event_types,
            requested_events: @requested_events
          ).load
        end
      end
    end
  end
end
