# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProductsEnablementTest < GitHub::TestCase
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
    @archived_repo = create(:archived_repository, owner: @organization, name: "archived-repo", created_by_user_id: @actor.id)

    # For enterprise
    GitHub.stubs(:dependency_graph_enabled?).returns(true)

    @security_configuration = create(
      :security_configuration, target: @organization, enable_ghas: true,
      code_scanning: "disabled",
      dependabot_alerts: "disabled",
      dependabot_security_updates: "disabled"
    )
  end

  [:removed, :removed_by_enterprise, :attaching, :updating, :detached].each do |state|
    test "does not apply config when unarchiving a repo with #{state} configuration state" do
      refute @archived_repo.maintained?

      orchestration = RepositoryOrchestration.unarchive(@archived_repo, actor: @actor)

      create(:repository_security_configuration,
        repository: @archived_repo,
        organization: @organization,
        security_configuration: @security_configuration,
        state:
      )
      if state == :enforced
        create(:security_configuration_policy, :enforced, security_configuration: @security_configuration, target: @organization)
      end

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        orchestration.execute(synchronous: true)

        # step :publish_unarchived
        assert_hydro_messages(count: 1, schema: "github.repositories.v1.Unarchived")

        assert_hydro_published({
          repository_id: @archived_repo.id,
          request_id: "",
          actor_id: @actor.id
        }, schema: "github.repositories.v1.Unarchived")

        repo_config = @archived_repo.repository_security_configuration.reload

        assert_no_changes -> { repo_config } do
          perform_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
            perform_hydro_message_job(
              { repository_id: @archived_repo.id },
              schema: "github.repositories.v1.Unarchived",
              queue: "hydro_security_products_enablement_repository_unarchived"
            )
          end
        end
      end

      assert orchestration.succeeded?
    end
  end

  test "does not apply config when unarchiving a repo without configuration state" do
    refute @archived_repo.maintained?
    assert_nil @archived_repo.repository_security_configuration

    orchestration = RepositoryOrchestration.unarchive(@archived_repo, actor: @actor)

    with_hydro_publisher(GitHub.sync_hydro_publisher) do
      orchestration.execute(synchronous: true)

      # step :publish_unarchived
      assert_hydro_messages(count: 1, schema: "github.repositories.v1.Unarchived")

      assert_hydro_published({
        repository_id: @archived_repo.id,
        request_id: "",
        actor_id: @actor.id
      }, schema: "github.repositories.v1.Unarchived")

      perform_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
        perform_hydro_message_job(
          { repository_id: @archived_repo.id },
          schema: "github.repositories.v1.Unarchived",
          queue: "hydro_security_products_enablement_repository_unarchived"
        )
      end

      assert_nil @archived_repo.repository_security_configuration
    end

    assert orchestration.succeeded?
  end

  [:attached, :enforced, :failed].each do |state|
    test "applies config when unarchiving a repo with #{state} configuration state" do
      GitHub.stubs(:dependency_graph_enabled?).returns(true)

      create(:repository_security_configuration,
        repository: @archived_repo,
        organization: @organization,
        security_configuration: @security_configuration,
        state:
      )
      if state == :enforced
        create(:security_configuration_policy, :enforced, security_configuration: @security_configuration, target: @organization)
      end

      refute @archived_repo.maintained?

      orchestration = RepositoryOrchestration.unarchive(@archived_repo, actor: @actor)

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        orchestration.execute(synchronous: true)

        # step :publish_unarchived
        assert_hydro_messages(count: 1, schema: "github.repositories.v1.Unarchived")

        assert_hydro_published({
          repository_id: @archived_repo.id,
          request_id: "",
          actor_id: @actor.id
        }, schema: "github.repositories.v1.Unarchived")

        SecurityProduct::ServiceManager.any_instance.stubs(:toggle_services_with_form_inputs)
        .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

        perform_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
          perform_hydro_message_job(
            { repository_id: @archived_repo.id },
            schema: "github.repositories.v1.Unarchived",
            queue: "hydro_security_products_enablement_repository_unarchived"
          )
        end
      end

      @archived_repo.reload

      assert orchestration.succeeded?
      refute @archived_repo.archived?
      expected_state = state == :enforced ? "enforced" : "attached"
      assert_equal expected_state, @archived_repo.repository_security_configuration.state
    end
  end
end
