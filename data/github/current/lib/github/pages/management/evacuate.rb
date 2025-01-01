# typed: false
# frozen_string_literal: true

require "logger"
require "github/pages/management/add_replica"
require "github/pages/management/remove_replica"

module GitHub::Pages::Management
  class Evacuate


    attr_reader :host, :delegate

    def initialize(host:, delegate:)
      @host = host
      @delegate = delegate
      @target_data_center = evacuating_hosts_datacenter unless GitHub.enterprise?
      nil
    end

    def perform
      unless self.class.evacuating_hosts.include?(host)
        delegate.log "Host=#{host} is not set to evacuating! Aborting evacuation."
        return false
      end

      ApplicationRecord::Domain::Repositories.connection.update(Arel.sql(<<-SQL, host: host))
        UPDATE pages_fileservers SET embargoed = 1 WHERE host = :host
      SQL

      succeeded = true

      delegate.log "Evacuating #{sites_to_evacuate.length} replicas"

      sites_to_evacuate.each_with_index do |(page_id, page_deployment_id), index|
        delegate.log "Evacuating page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect} (completed #{index} of #{sites_to_evacuate.length})"

        unless evacuate_single_site(page_id: page_id, page_deployment_id: page_deployment_id)
          delegate.log "Could not add new replica for page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect}. Retry later maybe?"
          succeeded = false
        end
      end

      succeeded
    end

    def non_voting
      @non_voting ||= ApplicationRecord::Domain::Repositories.connection.select_value(Arel.sql(<<-SQL, host: host))
        SELECT non_voting FROM pages_fileservers WHERE host = :host
      SQL
    end

    def self.evacuating_hosts
      ApplicationRecord::Domain::Repositories.connection.select_values(Arel.sql(<<-SQL))
        SELECT host FROM pages_fileservers WHERE evacuating = 1
      SQL
    end

    def evacuating_hosts_datacenter
      sql = ApplicationRecord::Domain::Repositories.connection.select_values(Arel.sql(<<-SQL, host: host))
                  SELECT datacenter FROM pages_fileservers WHERE host = :host
          SQL
      sql&.first
    end

    def sites_to_evacuate(limit: nil)
      (@sites_to_evacuate ||= {})[limit] ||= begin
        sql = Arel.sql(<<-SQL, host: host)
          SELECT pages_replicas.page_id, page_deployments.id
          FROM pages_replicas
          INNER JOIN pages ON pages.id = pages_replicas.page_id
          LEFT OUTER JOIN page_deployments ON page_deployments.id = pages_replicas.pages_deployment_id
          WHERE host = :host
        SQL
        sql += Arel.sql("LIMIT :limit", limit: Arel.sql(limit.to_s)) if limit

        ApplicationRecord::Domain::Repositories.connection.select_rows(sql)
      end
    end

    def evacuate_single_site(page_id:, page_deployment_id:)
      retries = 3
      result =
        begin
          AddReplica.new(page_id: page_id, page_deployment_id: page_deployment_id, delegate: delegate, voting: non_voting != 1, data_center: @target_data_center).perform
        rescue ActiveRecord::RecordNotUnique
          # This appears to be an unbounded loop, but it's actually bounded
          # by the number of online pages fileservers. This exception will
          # only be raised if we race with another Evacuate process and both
          # processes try to add a replica for the same pages site on the
          # same host at the same time. In this case, retrying will cause
          # AddReplica to pick a different server to replicate the site to.
          # If there are no servers available, #perform will return false
          # rather than raise an error.
          #
          # To be safe, we track whether or not a retry has occurred as well.
          retries -= 1
          retry unless retries == 0
        end

      succeeded = if result
        RemoveReplica.new(page_id: page_id, page_deployment_id: page_deployment_id, host: host, delegate: delegate).perform
      else
        false
      end

      stat_bit = succeeded ? "success" : "failure"
      GitHub.dogstats.increment("pages.management.evacuate.sites_evacuated", tags: ["status:#{stat_bit}"])
      GitHub.stats.increment("pages.management.evacuate.sites_evacuated.#{stat_bit}") if GitHub.enterprise?

      succeeded
    end
  end
end
