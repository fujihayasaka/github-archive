# typed: true
# frozen_string_literal: true

require "test_helper"

class UnarchiveRepositoryOrchestrationTest < GitHub::TestCase
  include HydroTestHelpers
  include HydroMessageJobTestHelpers

  fixtures do
    @actor = create(:user)
    @organization = create(:organization).tap do |organization|
      organization.add_admin(@actor)
    end
    @repository = create(:repository, owner: @organization, from_example: :simple).tap do |repository|
      repository.set_archived
      repository.send(:reset_archived)
    end
  end

  setup do
    RepositoryAuthVersion.delete_all
  end

  test "unarchive repository" do
    refute @repository.maintained?

    orchestration = RepositoryOrchestration.unarchive(@repository, actor: @actor)

    # step :instrument_unarchive
    GlobalInstrumenter.expects(:instrument).with("repository.archived_status_changed",
      {
        repository_id: @repository.id,
        repository_global_id: @repository.global_relay_id,
        is_archived: false,
        actor_id: @actor.id
      }
    ).once
    GlobalInstrumenter.expects(:instrument).with("search_indexing.repository_changed",
      {
        change: :UNARCHIVED,
        repository: @repository,
        auth_version: 2,
      }
    ).once
    Repository.any_instance.expects(:instrument).with(:unarchived, actor: @actor).once

    # step :update_search_index
    Search.expects(:add_to_search_index).with("bulk_issues", @repository.id, "purge" => true).once
    Search.expects(:add_to_search_index).with("bulk_discussions", @repository.id, "purge" => true).once
    Search.expects(:add_to_search_index).with("bulk_pull_requests", @repository.id, "purge" => true).once
    Search.expects(:add_to_search_index).with("repository", @repository.id).once

    # step :toggle_security_product_services
    security_product_service_manager = stub(:security_product_service_manager)
    security_product_service_manager.expects(:toggle_services_on_repository_state_changed).with(actor: @actor).once
    SecurityProduct::ServiceManager.expects(:new).with(@repository).returns(security_product_service_manager).once

    with_hydro_publisher(GitHub.sync_hydro_publisher) do
      orchestration.execute(synchronous: true)

      # step :publish_unarchived
      assert_hydro_messages(count: 1, schema: "github.repositories.v1.Unarchived")

      assert_hydro_published({
        repository_id: @repository.id,
        request_id: "",
        actor_id: @actor.id
      }, schema: "github.repositories.v1.Unarchived")
    end

    unless GitHub.enterprise?
      # step: redetect_manifest
      assert_enqueued_jobs 1, only: RepositoryDependencyRedetectJob
    end

    assert orchestration.succeeded?

    @repository.reload

    refute @repository.archived?
    assert @repository.maintained
    assert_nil @repository.archived_at
  end

  test "don't unarchive if repository is invalid" do
    refute @repository.maintained?

    @repository.name = "a" * 1000

    orchestration = RepositoryOrchestration.unarchive(@repository, actor: @actor)

    orchestration.execute

    refute orchestration.valid?

    assert_equal "Name is too long (maximum is 100 characters)", orchestration.errors&.where(:repository)&.map { |e| e.message }&.join(", ")

    @repository.reload

    assert @repository.archived?
    refute @repository.maintained
    assert @repository.archived_at
  end

  test "don't unarchive if organization is archived" do
    assert @organization.set_archived(@actor)
    refute @repository.maintained?

    orchestration = RepositoryOrchestration.unarchive(@repository, actor: @actor)

    orchestration.execute

    refute orchestration.valid?

    assert_equal "Owner is archived", orchestration.errors&.where(:repository)&.map { |e| e.message }&.join(", ")

    @repository.reload

    assert @repository.archived?
    refute @repository.maintained
    assert @repository.archived_at
  end

  test "failed unarchive rolls back changes" do
    @repository.create_repository_auth_version(version: 42)

    # Mock a failure during the auth_version increment, after the version is updated in the DB
    @repository.stubs(:reset_repository_auth_version).raises(StandardError.new("boom"))

    assert_predicate @repository, :archived?

    orchestration = RepositoryOrchestration.unarchive(@repository, actor: @actor)
    assert_raises StandardError do
      orchestration.execute(synchronous: true)
    end

    assert_equal 1, orchestration.attempts
    assert_equal "failed", orchestration.state
    assert_equal "boom", orchestration.error_message
    assert_equal "unarchive_repository", orchestration.step_name

    @repository.reload
    assert_predicate @repository, :archived?
    assert_equal 42, @repository.auth_version
  end

  test "increments the repository_auth_version", skip_enterprise: true do
    @repository.create_repository_auth_version(version: 42)

    # Freeze time so the hydro event timestamps match
    Timecop.freeze do
      RepositoryOrchestration.unarchive(@repository, actor: @actor).execute(synchronous: true)
      @repository.reload

      assert_equal 43, @repository.auth_version

      assert_hydro_published({
        change: :UNARCHIVED,
        repository: Hydro::EntitySerializer.repository(@repository),
        auth_version: 43,
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

      assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
    end
  end
end
