# typed: false
# frozen_string_literal: true

require "github/config/flipper"
require "feature_management"
require "database_selector/replication_state"
require "hydro/schemas/pages_dfs/v1/dfs_status_pb"
require "github/faraday_adapter/persistent_excon"
require "hydro/cutover_sink"
require "hydro/fallback_sink"
require "logger"

module GitHub::Pages::Management
  class SetEmbargoed

    attr_reader :host, :embargoed, :delegate

    def initialize(host:, embargoed:, delegate:)
      @host = host
      @embargoed = !!embargoed
      @delegate = delegate
      nil
    end

    def perform
      success = false
      datacenter = ApplicationRecord::Domain::PagesFromRepositories.connection.select_value(Arel.sql(<<-SQL, host: host))
        SELECT datacenter FROM pages_fileservers WHERE host = :host
      SQL
      return false unless datacenter.present?
      payload = {
        hostname: host,
        datacenter: datacenter,
        embargoed: { value: @embargoed },
      }
      result = GitHub.hydro_publisher.publish(
        payload,
        schema: "pages_dfs.v1.DfsStatus",
        topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 }
      )
      return false unless result.success?

      ApplicationRecord::Domain::PagesFromRepositories.transaction do
        # If trying to unembargo a host but it's evacuating, then fail.
        evacuating = ApplicationRecord::Domain::PagesFromRepositories.connection.select_value(Arel.sql(<<-SQL, host: host))
          SELECT evacuating FROM pages_fileservers WHERE host = :host FOR UPDATE
        SQL
        if evacuating.to_i != 0 && embargoed == false
          delegate.log "Cannot set embargoed=#{embargoed} for host=#{host} when evacuating=#{evacuating}"
          raise ActiveRecord::Rollback
        end

        unembargoed_hosts_in_dc = ApplicationRecord::Domain::PagesFromRepositories.connection.select_value(Arel.sql(<<-SQL, datacenter: datacenter))
          SELECT count(embargoed) FROM pages_fileservers WHERE datacenter = :datacenter AND embargoed = 0
        SQL

        if unembargoed_hosts_in_dc <= 2 && embargoed == true
          delegate.log "Cannot set embargoed=#{embargoed} for host=#{host} because there are only #{unembargoed_hosts_in_dc} unembargoed hosts in the same datacenter"
          raise ActiveRecord::Rollback
        end

        affected_rows = ApplicationRecord::Domain::PagesFromRepositories.connection.update(Arel.sql(<<-SQL, host: host, embargoed: embargoed))
          UPDATE pages_fileservers SET embargoed = :embargoed WHERE host = :host
        SQL

        if affected_rows == 0
          delegate.log "No such host=#{host}"
        else
          delegate.log "Set host=#{host} embargoed=#{embargoed}"
          success = true
        end
      end
      success
    end
  end
end
