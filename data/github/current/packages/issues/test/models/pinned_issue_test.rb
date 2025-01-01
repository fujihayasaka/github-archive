# typed: true
# frozen_string_literal: true

require "test_helper"

class PinnedIssueTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)

    @org = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org)

    @collaborator = create(:user)
    @repo.add_member(@collaborator)

    @issue1 = create(:issue, repository: @repo, user: @user)
  end

  context "hydro events" do
    test "sends hydro event on pin" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      @issue1.pin(actor: @user)

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(@user),
        repository: Hydro::EntitySerializer.repository(@repo),
        state: "PINNED",
        issue: Hydro::EntitySerializer.issue(@issue1),
      }
      assert_hydro_published(message, schema: "github.v1.IssuePinUpdated")
    end

    test "sends hydro event on unpin" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      @issue1.pin(actor: @user)
      @issue1.unpin(actor: @collaborator)

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(@collaborator),
        repository: Hydro::EntitySerializer.repository(@repo),
        state: "UNPINNED",
        issue: Hydro::EntitySerializer.issue(@issue1),
      }
      assert_hydro_published(message, schema: "github.v1.IssuePinUpdated")
    end
  end

  context "instrumentation" do
    test "instruments issue pinned" do
      events = subscribe "issue.pinned"
      @issue1.pin(actor: @user)

      expected_payload = {
        title: @issue1.title,
        body: @issue1.body,
        org: @org.login,
        org_id: @org.id,
      }

      assert event = events.pop, "An event was expected"
      assert_equal expected_payload[:org], event.payload[:org]
      assert_equal expected_payload[:org_id], event.payload[:org_id]
    end

    test "instruments issue unpinned" do
      @issue1.pin(actor: @user)
      events = subscribe "issue.unpinned"
      @issue1.unpin(actor: @collaborator)

      expected_payload = {
        title: @issue1.title,
        body: @issue1.body,
        org: @org.login,
        org_id: @org.id,
      }

      assert event = events.pop, "An event was expected"
      assert_equal expected_payload[:org], event.payload[:org]
      assert_equal expected_payload[:org_id], event.payload[:org_id]
    end
  end

  context "timeline events" do
    test "pinning a issue creates a pinned issue event" do
      @issue1.pin(actor: @user)

      pin_event = @issue1.events.last

      assert_equal "pinned", pin_event.event
      assert_equal @user, pin_event.actor
    end

    test "unpinning a issue creates a unpinned issue event" do
      @issue1.pin(actor: @user)
      @issue1.unpin(actor: @collaborator)

      unpin_event = @issue1.events.last

      assert_equal "unpinned", unpin_event.event
      assert_equal @collaborator, unpin_event.actor
    end
  end
end
