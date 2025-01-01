# typed: true
# frozen_string_literal: true

require "test_helper"

class ConvertedToDiscussionEventAdapterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    create(:profile, user: @user)
    @repository = create(:repository, owner: @user, has_discussions: true)
    @issue = create(:issue, repository: @repository)
    @discussion = create(:discussion, repository: @repository)

    @event = create(:issue_event,
      issue: @issue,
      event: "converted_to_discussion",
      subject: @discussion,
      actor: @repository.owner,
    )

    @loader = Issue::ShowLoader.new(
      @issue,
      @repository,
      @user,
      cap_filter: cap_authorizing_filter,
    )
  end

  test "adapting a conversion event does not execute any queries" do
    Platform::Security::RepositoryAccess.with_viewer(@user) do
      conversion_event = @loader.context.converted_to_discussion_events.first
      assert_equal @event, conversion_event
      _, queries = log_cleaned_queries do
        Issue::Adapter::ConvertedToDiscussionEventAdapter.new(@loader.context, event_id: conversion_event.id)
      end
      assert_equal 0, queries.count
    end
  end

  test "handles deleted discussion gracefully" do
    @discussion.destroy!
    loader = Issue::ShowLoader.new(
      @issue,
      @repository,
      @user,
      cap_filter: cap_authorizing_filter,
    )

    result = Issue::Adapter::ConvertedToDiscussionEventAdapter.new(
      loader.context,
      event_id: @event.id,
    )

    assert_nil result.discussion
  end
end
