# typed: true
# frozen_string_literal: true

require "test_helper"

class AbilityCollectionTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include DogstatsTestHelpers

  fixtures do
    @admin = create(:user)
    @org = create :organization, login: "org", admin: @admin
    @repo = create :repository, :minimal, owner: @org, name: "some-repo"
    @private_repo = create(:private_repository, :minimal, owner: @org, name: "some-private-repo")
    @integration = create(:integration, default_permissions: { "metadata" => :read })
  end

  context "#add_actor" do
    test "allows an IntegrationInstallation to be added as an actor" do
      result = @integration.install_on(
        @org,
        repositories: [@private_repo],
        installer: @admin,
        entry_point: :test_case
      )

      assert result.success?
      installation = result.installation

      @private_repo.resources.metadata.add_actor(installation, action: :read)
      assert_able installation, :read, @private_repo.resources.metadata
    end
  end

  context "#permit?" do
    test "returns true for a Bot whose integration has been installed with the specified permission on the subject" do
      version = @integration.versions.create(
        default_permissions: { "statuses" => :read },
      )

      installation = @integration.install_on(
        @private_repo.owner,
        repositories: [@private_repo],
        installer: @admin,
        version: version,
        entry_point: :test_case
      ).installation
      assert_able installation.bot, :read, @private_repo.resources.statuses
    end

    test "returns false for a Bot without a current installation" do
      bot = Bot.new
      refute_able bot, :read, @private_repo.resources.statuses
    end

    test "returns false for User without the specified permission on the subject" do
      user = create(:user)
      refute_able user, :read, @private_repo.resources.statuses
    end

    test "returns false for a Bot whose integration has not been installed with the specified permission on the subject" do
      installation = @integration.install_on(
        @repo.owner,
        repositories: [@repo],
        installer: @admin,
        entry_point: :test_case
      ).installation
      refute_able installation.bot, :read, @private_repo.resources.statuses
    end
  end

  test "removes all Permission records, if the parent is deleted" do
    version = @integration.versions.create(
      default_permissions: { "issues" => :write },
    )

    private_repo_two = create(:private_repository, :minimal, owner: @org, name: "some-other-private-repo")

    result = @integration.install_on(
      @org,
      repositories: [@private_repo, private_repo_two],
      installer: @admin,
      version: version,
      entry_point: :test_case
    )
    assert result.success?

    installation = result.installation

    refute_empty Permission.where(
      actor_id: installation.ability_id,
      actor_type: installation.ability_type,
      subject_id: @private_repo.ability_id,
    )

    # permissions get deleted when a repo is removed (soft-deleted)
    only = [IntegrationInstallationRepositoryRemovalJob]
    perform_enqueued_jobs(only: only) do
      perform_enqueued_hydro_jobs(only: [HydroDeleteInstallationsRepositoryDeletedJob], allowed_primary_query_count: 1) do
        @private_repo.remove(@admin, synchronous: true)
      end
    end

    assert_empty Permission.where(
      actor_id: installation.ability_id,
      actor_type: installation.ability_type,
      subject_id: @private_repo.ability_id,
    )

    assert_dogstats_distribution(1, "permissions_service.deleted_rows", tags: ["entry_point:hydro_message_handler_repo_removed_from_installations"])
  end
end
