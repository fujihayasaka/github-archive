# typed: true
# frozen_string_literal: true

require "logger"
require "github/routing"
require "github/pages/management"

module GitHub::Pages::Management
  class AddReplicaAzure
    attr_reader :page_id, :page_deployment_id, :host, :delegate, :data_center

    NoReplicasError = Class.new(GitHub::Pages::Management::ExecutionError)
    ReplicationFailedError = Class.new(GitHub::Pages::Management::ExecutionError)

    RSYNC_TIMEOUT = 600 # seconds
    RSYNC = "nice -n 19 ionice -c 3 rsync --rsync-path=\"nice -n 19 ionice -c 3 rsync\" --timeout=#{RSYNC_TIMEOUT}"

    def initialize(page_id:, page_deployment_id:, host: nil, delegate:, data_center: nil)
      @page_id = page_id
      @page_deployment_id = page_deployment_id
      @host = host
      @delegate = delegate
      @data_center = data_center
      nil
    end

    def perform

      if existing_replicas.empty?
        delegate.log "Could not find any existing replicas for page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect}. " \
          "Either the pages site does not exist on an online node or its data has been irrecoverably lost. Aborting."
        raise NoReplicasError, "No existing voting replicas for page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect}"
      end

      if host
        if existing_replicas.any? { |h, _rev| host == h }
          delegate.log "A replica of page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect} " \
            "already exists on #{host}. Aborting."
          return false
        end

        online = ApplicationRecord::Pages.connection.select_value(Arel.sql(<<-SQL, host: host))
          SELECT online FROM pages_fileservers WHERE host = :host
        SQL

        case online
        when nil
          delegate.log "#{host} is not a valid fileserver. Aborting."
          return false
        when 0
          delegate.log "#{host} is not online. Aborting."
          return false
        end
      else
        sql_bindings = {
          excluded_hosts: existing_replicas.map { |h, _r| h },
          data_center: data_center,
        }
        sql = Arel.sql(<<-SQL, **sql_bindings)
          SELECT host FROM pages_fileservers
          WHERE host NOT IN (:excluded_hosts)
            AND online = 1
            AND embargoed = 0
        SQL
        sql += Arel.sql("AND datacenter = :data_center", **sql_bindings) if data_center.present? && data_center != GitHub.default_datacenter
        sql += Arel.sql("ORDER BY disk_free DESC, host ASC LIMIT 1")

        @host = ApplicationRecord::Pages.connection.select_value(sql)
        unless host
          delegate.log "Couldn't find any available hosts for new replica"
          return false
        end
      end

      existing_replicas.each do |existing_replica_host, revision, _|
        delegate.log "Attempting to restore from existing replica on #{existing_replica_host}..."

        if revision.nil? # this happens, you know.
          delegate.log "No revision for replica on #{existing_replica_host}! Trying something else..."
          next
        end

        # proxima will do rsync content within the update replica api call
        unless GitHub.multi_tenant_enterprise?
          path = GitHub::Routing.dpages_storage_path(page_id, revision: revision)

          next unless delegate.ssh(host, "mkdir -p #{path}", timeout: 5)

          next unless delegate.ssh(existing_replica_host, "#{RSYNC} -a #{path}/ #{host}:#{path}/", timeout: RSYNC_TIMEOUT)

          next unless delegate.ssh(host, "test -d #{path}", timeout: 5)
        end

        if add_replica(host: host, page_id: page_id, page_deployment_id: page_deployment_id, revision: revision)
          delegate.log "Successfully replicated site to #{host}"
          GitHub.dogstats.increment("pages.management.add_replica.count")
          GitHub.stats.increment("pages.management.add_replica.count") if GitHub.enterprise?
          return true
        else
          delegate.log "Pages site has been rebuilt since script started. Aborting."
          return false
        end
      end

      delegate.log "Failed to create new replica from any existing replica. Aborting."

      raise ReplicationFailedError, "Failed to create new replica from any existing replica for page_id=#{page_id} and page_deployment_id=#{page_deployment_id.inspect}"
    end

    def add_replica(host:, page_id:, page_deployment_id:, revision:, find_revision: false)
      if find_revision
        if existing_replicas.empty?
          delegate.log "Could not find any existing replicas for page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect}. " \
            "Either the pages site does not exist on an online node or its data has been irrecoverably lost. Aborting."
          return false
        end
        revision = existing_replicas.first[1]
      end

      # legacy: no page_deployment_id
      if page_deployment_id.nil?
        return add_replica_legacy(host: host, page_id: page_id, revision: revision)
      end

      success = T.let(true, T::Boolean)

      # new hotness: page_deployments table
      ApplicationRecord::Pages.transaction do
        current_revision = ApplicationRecord::Pages.connection.select_value(Arel.sql(<<-SQL, page_deployment_id: page_deployment_id))
          SELECT revision FROM page_deployments
          WHERE id = :page_deployment_id
          FOR UPDATE
        SQL

        # compare the current built revision to the one we think we're
        # updating before inserting a new replica record.
        # the select statement above locks the page_deployments row to prevent this check
        # from racing with concurrent updates elsewhere.
        if current_revision != revision
          success = false
          raise ActiveRecord::Rollback
        end

        if GitHub.multi_tenant_enterprise?
          client = Page::Twirp::RequestClient.new(service_name: "repair")
          client.update_replica(page_id: page_id, deployment_id: page_deployment_id, replica_to_add: [host], replica_to_remove: [], path: GitHub::Routing.dpages_storage_path(page_id, revision: revision))
        end

        ApplicationRecord::Pages.connection.insert(Arel.sql(<<-SQL, page_id: page_id, page_deployment_id: page_deployment_id, host: host))
          INSERT INTO pages_replicas (page_id, pages_deployment_id, host, created_at, updated_at)
          VALUES (:page_id, :page_deployment_id, :host, NOW(), NOW())
        SQL
      end

      success
    end

    private

    # add a pages_replica which links directly to the pages table without using
    # the new page_deployments table as intermediary. this is legacy and this method
    # should not be called directly. use #add_replica instead.
    def add_replica_legacy(host:, page_id:, revision:)
      success = T.let(true, T::Boolean)

      # legacy: pages_replicas connect directly to pages
      ApplicationRecord::Pages.transaction do
        current_revision = ApplicationRecord::Pages.connection.select_value(Arel.sql(<<-SQL, page_id: page_id))
          SELECT built_revision FROM pages
          WHERE id = :page_id
          FOR UPDATE
        SQL

        # compare the current built_revision to the one we think we're
        # updating before inserting a new replica record.
        # the select statement above locks the pages row to prevent this check
        # from racing with concurrent updates elsewhere.
        if current_revision != revision
          success = false
          raise ActiveRecord::Rollback
        end
        ApplicationRecord::Pages.connection.insert(Arel.sql(<<-SQL, page_id: page_id, host: host))
          INSERT INTO pages_replicas (page_id, host, created_at, updated_at)
          VALUES (:page_id, :host, NOW(), NOW())
        SQL
      end

      success
    end

    def existing_replicas
      @existing_replicas ||= begin
        results =
          if page_deployment_id
            # Grab the replicas with the correct page deployment.
            ApplicationRecord::Pages.connection.select_rows(Arel.sql(<<-SQL, page_id: page_id, page_deployment_id: page_deployment_id))
              SELECT pages_replicas.host, page_deployments.revision, pages_fileservers.non_voting FROM pages
              INNER JOIN page_deployments ON page_deployments.page_id = pages.id
              INNER JOIN pages_replicas ON pages_replicas.pages_deployment_id = page_deployments.id
              INNER JOIN pages_fileservers ON pages_fileservers.host = pages_replicas.host
              WHERE pages_fileservers.online = 1 AND pages.id = :page_id AND page_deployments.id = :page_deployment_id
            SQL
          else
            # Grab the legacy replicas without any page deployment.
            ApplicationRecord::Pages.connection.select_rows(Arel.sql(<<-SQL, page_id: page_id))
              SELECT pages_replicas.host, pages.built_revision, pages_fileservers.non_voting FROM pages
              INNER JOIN pages_replicas ON pages_replicas.page_id = pages.id
              INNER JOIN pages_fileservers ON pages_fileservers.host = pages_replicas.host
              WHERE pages_fileservers.online = 1 AND pages.id = :page_id AND pages_replicas.pages_deployment_id IS NULL
            SQL
          end

        results
      end
    end
  end
end
