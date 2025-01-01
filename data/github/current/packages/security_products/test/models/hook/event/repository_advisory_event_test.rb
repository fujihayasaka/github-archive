# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventRepositoryAdvisoryEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @org = create :organization, admin: @user
    @repo = create(:public_repository, owner: @org, from_example: :simple)
    @repository_advisory = create :draft_repository_advisory, repository: @repo, author: @user
    @repository_advisory.set_published
  end

  test "action is required" do
    assert_event_required_attributes(Hook::Event::RepositoryAdvisoryEvent, :action)
  end

  test "repository_advisory_id is required" do
    assert_event_required_attributes(Hook::Event::RepositoryAdvisoryEvent, :repository_advisory_id)
  end

  test "action returns the correct value" do
    event = Hook::Event::RepositoryAdvisoryEvent.new(
      action: :published,
      repository_advisory_id: @repository_advisory.id,
    )

    assert_equal :published, event.action
  end

  test "repository_advisory returns the correct record" do
    event = Hook::Event::RepositoryAdvisoryEvent.new(
      action: :published,
      repository_advisory_id: @repository_advisory.id,
    )

    assert_equal @repository_advisory, event.repository_advisory
  end

  test "actor returns publisher of the repo advisory for publish action" do
    event = Hook::Event::RepositoryAdvisoryEvent.new(
      action: :published,
      repository_advisory_id: @repository_advisory.id,
    )

    assert_equal event.actor, @repository_advisory.publisher
  end

  test "actor returns author of the repo advisory for report action" do
    event = Hook::Event::RepositoryAdvisoryEvent.new(
      action: :reported,
      repository_advisory_id: @repository_advisory.id,
    )

    assert_equal event.actor, @repository_advisory.author
  end

  test "target repository and organization returns the correct record" do
    event = Hook::Event::RepositoryAdvisoryEvent.new(
      action: :published,
      repository_advisory_id: @repository_advisory.id,
    )
    assert_equal @repository_advisory.repository, event.target_repository
    assert_equal @repository_advisory.repository.owner, event.target_organization
  end
end
