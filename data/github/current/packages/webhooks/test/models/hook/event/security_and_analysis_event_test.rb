# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventSecurityAndAnalysisEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user)
    @repo = create(:private_repository, owner: @org)
    @user_repo = create(:public_repository, owner: @user)
    @changes = {
      from: {
        security_and_analysis: Api::Serializer.serialize(:security_and_analysis_hash, @repo)
      }
    }
  end

  setup do
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    SecurityProduct::AdvancedSecurity.any_instance.stubs(:enabled?).returns(true)
    SecretScanning::Features::Repo::TokenScanning.new(@repo).enable(actor: @user)
  end

  context "#repository_id" do
    test "is required" do
      assert_event_required_attributes Hook::Event::SecurityAndAnalysisEvent, :repository_id
    end
  end

  context "#actor_id" do
    test "is required" do
      assert_event_required_attributes Hook::Event::SecurityAndAnalysisEvent, :actor_id
    end
  end

  context "#changes" do
    test "is required" do
      assert_event_required_attributes Hook::Event::SecurityAndAnalysisEvent, :changes
    end
  end

  context "#target_repository" do
    test "returns the specified target_repository" do
      assert_equal @org, event.target_organization
    end

    test "returns nil if repo doesn't exist" do
      event = Hook::Event::SecurityAndAnalysisEvent.new(repository_id: -1, actor_id: @user.id, changes: @changes)
      assert_nil event.target_organization
    end
  end

  context "#target_organization" do
    test "returns the specified target repository owner" do
      assert_equal @org, event.target_organization
    end

    test "returns empty if not owned by org" do
      event = Hook::Event::SecurityAndAnalysisEvent.new(repository_id: @user_repo.id, actor_id: @user.id, changes: @changes)
      assert_nil event.target_organization
    end

    test "returns nil if repo doesn't exist" do
      event = Hook::Event::SecurityAndAnalysisEvent.new(repository_id: -1, actor_id: @user.id, changes: @changes)
      assert_nil event.target_organization
    end
  end

  context "#deliverable?" do
    test "returns true if the repo exists." do
      assert event.deliverable?
    end

    test "returns false if the repo does not exist" do
      event = Hook::Event::SecurityAndAnalysisEvent.new(repository_id: -1, actor_id: @user.id, changes: @changes)
      refute event.deliverable?
    end
  end

  context "#actor" do
    test "returns specified actor" do
      assert_equal @user, event.actor
    end
  end

  context "#changes" do
    test "returns specified changes" do
      assert_equal @changes, event.changes
    end
  end

  def event
    @event ||= Hook::Event::SecurityAndAnalysisEvent.new(repository_id: @repo.id, actor_id: @user.id, changes: @changes)
  end
end
