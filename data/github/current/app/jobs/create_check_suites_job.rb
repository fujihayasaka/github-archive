# typed: true
# frozen_string_literal: true

class CreateCheckSuitesJob < ApplicationJob
  include GitHub::Tracing

  queue_as :create_check_suites

  include Repositories::Domain::Provider

  trace_method(
    :perform,
    span_attribute_extractor: -> (_instance, *args, **_kwargs) do
      {
        "push_id" => args[0],
        "repository_id" => args[1],
      }
    end
  )
  trace_method :perform_with_replica_reads
  trace_method :perform_with_primary_reads
  trace_method :create_check_suite

  retry_on_dirty_exit

  resolve_tenant_context do |_, repository_id|
    Repositories::Public.resolve_tenant(id: repository_id)
  end

  def self.enqueue(push_id:, repository_id:)
    CreateCheckSuitesJob.perform_later(push_id, repository_id)
  end

  def perform(push_id, repository_id)
    push = repositories_domain.pushes.by_id_and_repo_id(repository_id: repository_id, id: push_id)
    return unless push

    repository = repositories_domain.by_id(repository_id, allow_deleted: true)
    return unless repository

    installations_with_access = IntegrationInstallation.with_resources_on(
      subject: repository,
      resources: "checks",
      min_action: :write,
    )

    installations_with_access.each do |installation|
      # rubocop:todo GitHub/AvoidCast
      if CheckSuites::Public.request_checks_for_push?(push: push) || T.cast(repository, Repository).auto_trigger_checks_for?(
          app_id: installation.integration_id)
        with_write { create_check_suite repository, push, installation, {} }
      end
      # rubocop:enable GitHub/AvoidCast
    end
  end

  def create_check_suite(repository, push, installation, request_opts)
    attrs = {
      github_app_id: installation.integration_id,
      head_sha: push.after,
      repository_id: repository.id,
    }

    check_suite = CheckSuite.find_by(attrs)

    return if check_suite

    attrs.merge!(
      push_id: push.id,
      creator_id: push.pusher_id,
      head_branch: push.branch_name,
    )

    check_suite = CheckSuite.create_and_rescue_uniqueness(attrs)
    GitHub.dogstats.increment("checks.create_suite.nil_push", tags: ["where:create_job"]) unless push
    check_suite.validate!

    check_suite.request(**request_opts)
  end
end
