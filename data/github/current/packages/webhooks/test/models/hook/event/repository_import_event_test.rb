# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventRepositoryImportEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @org = create(:organization)
    @repo = create(:repository, owner: @org)
    @actor = create(:user, login: "user")
    @status = "success"
  end

  def repository_import_event(
    status: @status, repository_id: @repo.id, actor_id: @actor.id
  )
    Hook::Event::RepositoryImportEvent.new(
      status:        status,
      repository_id: repository_id,
      actor_id:      actor_id,
    )
  end

  test "required attributes" do
    assert_event_required_attributes(
      Hook::Event::RepositoryImportEvent,
      :status, :repository_id, :actor_id
    )
  end

  context "#status" do
    test "returns the status of the repository import event" do
      assert_equal(@status, repository_import_event.status)
    end
  end

  context "#feature_flagged?" do
    test "returns true when GitHub.porter_available? is false" do
      GitHub.stubs(:porter_available?).returns(false)

      assert(Hook::Event::RepositoryImportEvent.feature_flagged?)
      assert(repository_import_event.feature_flagged?)
    end

    test "returns false when GitHub.porter_available? is true" do
      GitHub.stubs(:porter_available?).returns(true)

      refute(Hook::Event::RepositoryImportEvent.feature_flagged?)
      refute(repository_import_event.feature_flagged?)
    end
  end

  context "#target_repository" do
    test "returns the repository of the repository import event" do
      assert_equal(@repo, repository_import_event.target_repository)
    end
  end

  context "#actor" do
    test "returns the actor of the repository import event" do
      assert_equal(@actor, repository_import_event.actor)
    end
  end

  context "#deliverable?" do
    test "returns false if a Repository is not found" do
      event = repository_import_event(repository_id: -1)

      refute_predicate(event, :deliverable?)
    end

    test "returns false if a User is not found" do
      event = repository_import_event(actor_id: -1)

      refute_predicate(event, :deliverable?)
    end

    test "returns true if a Repository and a User are found" do
      assert_predicate(repository_import_event, :deliverable?)
    end
  end
end
