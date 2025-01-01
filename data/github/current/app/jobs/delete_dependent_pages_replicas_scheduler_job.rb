# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# DeleteDependentPagesReplicasSchedulerJob finds all the hosts that exist in pages_replicas
# but don't exist in pages_fileservers, and schedules their background deletion from pages_replicas.
class DeleteDependentPagesReplicasSchedulerJob < ApplicationJob
  # This job is a background maintenance task that works across a stamp.
  exempt_from_tenant_context_requirement

  queue_as :background_destroy

  locked_by key: ->(_job) { "delete_dependent_pages_replicas_scheduler" }, timeout: 5.minutes

  def perform(*args)
    Page::Replica.throttle do
      nonextant_hosts = if GitHub.flipper[:pages_killed_queries].enabled?
        Page::Replica.group(:host).pluck(:host) - Page::FileServer.group(:host).pluck(:host)
      else
        Page::Replica.connection.select_values(Arel.sql(<<~SQL))
          SELECT DISTINCT(pages_replicas.host) FROM pages_replicas
          WHERE pages_replicas.host NOT IN (SELECT host FROM pages_fileservers)
        SQL
      end

      nonextant_hosts.each { |h| DeleteDependentPagesReplicasJob.perform_later(h) }
    end
  end

  retry_on_dirty_exit
end
