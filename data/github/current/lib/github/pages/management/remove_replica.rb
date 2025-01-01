# typed: false
# frozen_string_literal: true

require "logger"

module GitHub::Pages::Management
  class RemoveReplica

    attr_reader :page_id, :page_deployment_id, :host, :delegate

    def initialize(page_id:, page_deployment_id:, host:, delegate:)
      @page_id = page_id
      @page_deployment_id = page_deployment_id
      @host = host
      @delegate = delegate
      nil
    end

    def perform
      success = false

      # Use Page::Deployment as our base class for transacting because
      # there is no guarantee that the pages_replicas table will be on the
      # same MySQL cluster & connection as ActiveRecord::Base.
      # There is a reasonable expectation that page_deployments and pages_replicas
      # will always be part of the same MySQL cluster & therefore accessible
      # via the same connection.
      ApplicationRecord::Domain::Repositories.transaction do
        if page_deployment_id
          # new hotness: use a page_deployments row to allow preview deployments
          current_replica_count = ApplicationRecord::Domain::Repositories.connection.select_value(Arel.sql(<<-SQL, page_id: page_id, page_deployment_id: page_deployment_id)).to_i
            SELECT COUNT(*) FROM pages_replicas
            WHERE page_id = :page_id AND pages_deployment_id = :page_deployment_id
            FOR UPDATE
          SQL

          # Rebuilds from source cannot be guaranteed, so at least guarantee we
          # have 1 replica. Block removal of the last replica.
          if current_replica_count <= 1
            delegate.log "Add a replica before removing one! You must have at least 1 replica."
            raise ActiveRecord::Rollback
          end

          affected_rows = ApplicationRecord::Domain::Repositories.connection.delete(Arel.sql(<<-SQL, page_id: page_id, page_deployment_id: page_deployment_id, host: host))
            DELETE FROM pages_replicas WHERE page_id = :page_id AND pages_deployment_id = :page_deployment_id AND host = :host
          SQL
        else
          # legacy: pages_replicas don't use pages_deployment_id and connect straight to pages table
          current_replica_count = ApplicationRecord::Domain::Repositories.connection.select_value(Arel.sql(<<-SQL, page_id: page_id)).to_i
            SELECT COUNT(*) FROM pages_replicas
            WHERE page_id = :page_id AND pages_deployment_id IS NULL
            FOR UPDATE
          SQL

          # Rebuilds from source cannot be guaranteed, so at least guarantee we
          # have 1 replica. Block removal of the last replica.
          if current_replica_count <= 1
            delegate.log "Add a replica before removing one! You must have at least 1 replica."
            raise ActiveRecord::Rollback
          end

          affected_rows = ApplicationRecord::Domain::Repositories.connection.delete(Arel.sql(<<-SQL, page_id: page_id, host: host))
            DELETE FROM pages_replicas WHERE page_id = :page_id AND host = :host AND pages_deployment_id IS NULL
          SQL
        end

        if affected_rows == 0
          delegate.log "No replica of page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect} on host=#{host}"
        else
          delegate.log "Removed replica of page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect} on host=#{host}"
          GitHub.dogstats.increment("pages.management.remove_replica.count")
          GitHub.stats.increment("pages.management.remove_replica.count") if GitHub.enterprise?
          success = true
        end
      end

      success
    end
  end
end
