# typed: true
# frozen_string_literal: true
require "test_helper"
require "test_helpers/job_test_helper"

class MassInstallAutomaticIntegrationsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @repo = create(:repository, :minimal)
    # If we are testing for Enterprise, ensure Dependency Graph is enabled
    # as it is a prerequisite of Repository#enable_vulnerability_updates
    GitHub.stubs(dependency_graph_enabled?: true)
    @repo.enable_vulnerability_updates(actor: @repo.owner)

    make_trusted_oauth_apps_owner
    @dependabot_app = create(:dependabot_integration)

    @trigger = create(
      :integration_install_trigger,
      integration: @dependabot_app,
      install_type: :pending_dependabot_installation_requested,
    )

    @pending_installation = make_pending_automatic_installation(
      target: @repo,
      trigger_type: :pending_dependabot_installation_requested,
    )

    @job = MassInstallAutomaticIntegrationsJob
  end

  test "it's an InstallAutomaticIntegrations job but with dedicated queue" do
    job = MassInstallAutomaticIntegrationsJob

    assert job.new.is_a?(InstallAutomaticIntegrationsJob)
    assert_equal "mass_install_automatic_integrations", job.queue_name
  end

  context "instrumentation" do
    test "metrics include a mass_install_automatic_integrations tag" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @job.perform_now(
        @repo.owner.id,
        @dependabot_app.id,
        @trigger.id,
        [@repo.id],
        {
          "pending_automatic_installation_id" => @pending_installation.id,
          :entry_point => :test_case
        },
      )

      stats = GitHub.dogstats.increments(
        "jobs.install_automatic_integrations.installed",
        tags: ["installation_queue:mass_install_automatic_integrations"],
      )
      assert_equal 1, stats.count

      dist_stats = GitHub.dogstats.distributions(
        "jobs.install_automatic_integrations.mean_time_to_install.dist",
        tags: ["installation_queue:mass_install_automatic_integrations"],
      )
      assert_equal 1, dist_stats.count
    end

    test "time to install is stored in redis" do
      key = MassInstallAutomaticIntegrationsJob::TIME_TO_INSTALL_KEY
      redis = GitHub.job_coordination_redis
      redis.del(key) # poor man's flush

      @job.perform_now(
        @repo.owner.id,
        @dependabot_app.id,
        @trigger.id,
        [@repo.id],
        {
          "pending_automatic_installation_id" => @pending_installation.id,
          "enqueued_timestamp" => 3.seconds.ago.to_i,
          :entry_point => :test_case
        }
      )

      assert @dependabot_app.installed_on?(@repo.owner), "expected #{@dependabot_app} to be installed on #{@repo.owner}"
      assert_predicate redis.get(key), :present?
    end

    test "retry conditions" do
      assert_retry_on_dirty_exit job: MassInstallAutomaticIntegrationsJob, args: [@repo.owner.id, @dependabot_app.id, @trigger.id, [@repo.id], {
        "pending_automatic_installation_id" => @pending_installation.id,
        "enqueued_timestamp" => 3.seconds.ago.to_i,
      }]

      assert_retry_on_throttler_error job: MassInstallAutomaticIntegrationsJob, args: [@repo.owner.id, @dependabot_app.id, @trigger.id, [@repo.id], {
        "pending_automatic_installation_id" => @pending_installation.id,
        "enqueued_timestamp" => 3.seconds.ago.to_i,
      }]
    end
  end
end
