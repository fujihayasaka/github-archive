# typed: true
# frozen_string_literal: true

require "test_helper"

class ArchiveRepositoryOrchestrationTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @repository = create(:repository, from_example: :simple)
    @actor = create(:user)
  end

  setup do
    @repository.send(:reset_archived)
    RepositoryAuthVersion.delete_all
  end

  test "archive repository" do
    orchestration = RepositoryOrchestration.archive(@repository, actor: @actor)

    # step :instrument_archive
    GlobalInstrumenter.expects(:instrument).with("repository.archived_status_changed",
      {
        repository_id: @repository.id,
        repository_global_id: @repository.global_relay_id,
        is_archived: true,
        actor_id: @actor.id
      }
    ).once
    GlobalInstrumenter.expects(:instrument).with("search_indexing.repository_changed",
      {
        change: :ARCHIVED,
        repository: @repository,
        auth_version: 2,
      }
    ).once
    Repository.any_instance.expects(:instrument).with(:archived, actor: @actor).once

    # step :update_search_index
    Search.expects(:add_to_search_index).with("bulk_issues", @repository.id, "purge" => true).once
    Search.expects(:add_to_search_index).with("bulk_discussions", @repository.id, "purge" => true).once
    Search.expects(:add_to_search_index).with("bulk_pull_requests", @repository.id, "purge" => true).once
    Search.expects(:add_to_search_index).with("repository", @repository.id).once

    # step :toggle_security_product_services
    Repository.any_instance.expects(:toggle_security_product_on_archive).with(@actor).once

    with_hydro_publisher(GitHub.sync_hydro_publisher) do
      orchestration.execute(synchronous: true)

      # step :publish_archived
      assert_hydro_messages(count: 1, schema: "github.repositories.v1.Archived")

      assert_hydro_published({
        repository_id: @repository.id,
        request_id: "",
        actor_id: @actor.id
      }, schema: "github.repositories.v1.Archived")
    end

    assert orchestration.succeeded?

    @repository.reload

    assert @repository.archived?
    refute @repository.maintained
    assert @repository.archived_at
  end

  test "don't archive if repository is invalid" do
    @repository.name = "a" * 1000

    orchestration = RepositoryOrchestration.archive(@repository, actor: @actor)

    orchestration.execute

    refute orchestration.valid?

    assert_equal "Name is too long (maximum is 100 characters)", orchestration.errors&.where(:repository)&.map { |e| e.message }&.join(", ")

    @repository.reload

    refute @repository.archived?
    assert @repository.maintained
    assert_nil @repository.archived_at
  end

  test "failed archive rolls back changes" do
    @repository.create_repository_auth_version(version: 42)

    GitHub.flipper[:geyser_denylist].disable

    # Mock a failure during the auth_version increment, after the version is updated in the DB
    @repository.stubs(:reset_repository_auth_version).raises(StandardError.new("boom"))

    refute_predicate @repository, :archived?

    orchestration = RepositoryOrchestration.archive(@repository, actor: @actor)
    assert_raises StandardError do
      orchestration.execute(synchronous: true)
    end

    assert_equal 1, orchestration.attempts
    assert_equal "failed", orchestration.state
    assert_equal "boom", orchestration.error_message
    assert_equal "archive_repository", orchestration.step_name

    @repository.reload
    refute_predicate @repository, :archived?
    assert_equal 42, @repository.auth_version
  end

  test "increments the repository_auth_version", skip_enterprise: true do
    @repository.create_repository_auth_version(version: 42)

    GitHub.flipper[:geyser_denylist].disable

    # Freeze time so the hydro event timestamps match
    Timecop.freeze do
      RepositoryOrchestration.archive(@repository, actor: @actor).execute(synchronous: true)
      @repository.reload

      assert_equal 43, @repository.auth_version

      assert_hydro_published({
        change: :ARCHIVED,
        repository: Hydro::EntitySerializer.repository(@repository),
        auth_version: 43,
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

      assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
    end
  end
end
