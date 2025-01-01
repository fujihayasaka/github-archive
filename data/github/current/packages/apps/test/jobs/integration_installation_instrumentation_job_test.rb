# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class IntegrationInstallationInstrumentationJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @org = create(:organization)
    @admin = @org.admins.first
    @repo = create(:repository, :minimal, owner: @org)
    @repo_1 = create(:repository, :minimal, owner: @org)
  end

  context "repositories added" do
    test "instruments the addition of the repositories" do
      installation = make_integration_installation(target: @org, repository: @repo, permissions: { "metadata" => :read })
      integration = installation.integration
      events = subscribe "integration_installation.repositories_added"

      perform_enqueued_jobs(only: [DeliverHookEventJob]) do
        IntegrationInstallationInstrumentationJob.perform_now(
          :repositories_added,
          installation.id,
          @org.admins.first.id,
          [@repo_1.id],
          "selected",
        )
      end

      expected_payload = {}.tap do |payload|
        payload[:installation_id]          = installation.id
        payload[:actor]                    = @admin.login
        payload[:actor_id]                 = @admin.id
        payload[:integration]              = integration.name
        payload[:app]                      = integration.name
        payload[:integration_id]           = integration.id
        payload[:app_id]                   = integration.id
        payload[:name]                     = integration.name
        payload[:slug]                     = integration.slug
        payload[:org]                      = @org.to_s
        payload[:org_id]                   = @org.id
        payload[:repositories_added]       = [@repo_1.id]
        payload[:repositories_added_names] = [@repo_1.full_name]
        payload[:repository_selection]     = "selected"
        payload[:requester_id]             = nil

      end

      assert event = events.pop, "not instrumented"
      assert_same_hash expected_payload, event.payload
    end

    test "reports as automatically added if performed by a Bot" do
      installation = make_integration_installation(target: @org, repository: @repo, permissions: { "metadata" => :read })
      integration = installation.integration
      events = subscribe "integration_installation.repositories_added"

      perform_enqueued_jobs(only: [DeliverHookEventJob]) do
        IntegrationInstallationInstrumentationJob.perform_now(
          :repositories_added,
          installation.id,
          installation.bot.id,
          [@repo_1.id],
          "selected",
        )
      end

      expected_payload = {
        app: integration.name,
        org: @org.to_s,
        actor: integration.bot.display_login,
        name: integration.name,
        slug: integration.slug,
        app_id: integration.id,
        org_id: @org.id,
        actor_id: integration.bot.id,
        integration: integration.name,
        requester_id: nil,
        integration_id: integration.id,
        installation_id: installation.id,
        repositories_added: [@repo_1.id],
        repositories_added_names: [@repo_1.full_name],
        repository_selection: "selected",
        added_automatically: true,
      }

      assert event = events.pop, "not instrumented"
      assert_same_hash expected_payload, event.payload
    end
  end

  context "failure" do
    test "retry conditions" do
      installation = make_integration_installation(target: @org, repositories: [@repo, @repo_1], permissions: { "metadata" => :read })
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      assert_retry_on_dirty_exit job: IntegrationInstallationInstrumentationJob, args: [:repositories_added, installation.id, @admin.id, [@repo, @repo_1], "selected"]
      assert_equal 1, GitHub.dogstats.increments("active_job.retry", tags: [
        "class:integration_installation_instrumentation_job",
      ]).length
    end
  end

  context "repositories removed" do
    test "instruments the removal of the repositories" do
      installation = make_integration_installation(target: @org, repositories: [@repo, @repo_1], permissions: { "metadata" => :read })
      integration = installation.integration
      events = subscribe "integration_installation.repositories_removed"

      IntegrationInstallationInstrumentationJob.perform_now(
        :repositories_removed,
        installation.id,
        @org.admins.first.id,
        [@repo_1.id],
        "selected",
      )

      expected_payload = {}.tap do |payload|
        payload[:installation_id]            = installation.id
        payload[:actor]                      = @admin.display_login
        payload[:actor_id]                   = @admin.id
        payload[:integration]                = integration.name
        payload[:app]                        = integration.name
        payload[:integration_id]             = integration.id
        payload[:app_id]                     = integration.id
        payload[:name]                       = integration.name
        payload[:slug]                       = integration.slug
        payload[:org]                        = @org.to_s
        payload[:org_id]                     = @org.id
        payload[:repositories_removed]       = [@repo_1.id]
        payload[:repositories_removed_names] = [@repo_1.full_name]
        payload[:repository_selection]       = "selected"

      end

      assert event = events.pop, "not instrumented"
      assert_equal expected_payload, event.payload
    end
  end

  test "retry conditions" do
    installation = make_integration_installation(target: @org, repositories: [@repo, @repo_1], permissions: { "metadata" => :read })
    integration = installation.integration
    events = subscribe "integration_installation.repositories_removed"

    assert_retry_on_dirty_exit job: IntegrationInstallationInstrumentationJob, args: [
      installation.id,
      @org.admins.first.id,
      [@repo_1.id],
      "selected",
    ]
  end
end
