# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroStratocasterRepositoryVisibilityChangedJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @repo1 = create(:public_repository)
    @repo2 = create(:public_repository)
  end

  setup do
    @store = GitHub.stratocaster.instance_variable_get(:@store)
    GitHub.stratocaster.instance_variable_set(:@store, Stratocaster::Mysql2Store.new)
    GitHub.stratocaster.trigger("PublicEvent", @repo1.id)
    GitHub.stratocaster.trigger("PublicEvent", @repo2.id)
  end

  teardown do
    GitHub.stratocaster.instance_variable_set(:@store, @store)
  end

  test "it works" do
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @repo1.set_visibility(actor: @repo1.owner, visibility: "private") }

    assert_equal 1, GitHub.stratocaster.events("repo:#{@repo1.id}").count
    message = {
      repository_id: @repo1.id,
      actor_id: @repo1.owner.id,
      new_visibility: Repository::PRIVATE_VISIBILITY,
      old_visibility: Repository::PUBLIC_VISIBILITY,
    }

    assert_changes -> { GitHub.stratocaster.events("repo:#{@repo1.id}").count }, -1 do
      perform_hydro_message_job(message, schema: "github.repositories.v1.VisibilityChanged", queue: "hydro_stratocaster_repository_visibility_changed")
    end
  end
end
