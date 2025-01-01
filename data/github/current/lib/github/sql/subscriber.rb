# typed: true
# frozen_string_literal: true

module GitHub
  class SQL
    class Subscriber
      # Private: The regex to match select queries.
      COMMENT_REGEXP = /\/\*(?:[^*]|\*[^\/])*\*\//mi.freeze
      OPT_COMMENT_REGEXP = /(?:(?:#{COMMENT_REGEXP}[\s]*)|\A)/mi.freeze

      # Private: The regex to match an optional leading comment segment.
      SELECT_REGEXP = /#{OPT_COMMENT_REGEXP}select.*?from\s*`?([\w$]+)`?\.?`?([\w$]+)?`?/mi.freeze

      # Private: These all need to be liberal about allowing keywords like
      # LOW_PRIORITY, IGNORE, QUICK, etc. in between the verb and the
      # other keywords.
      INSERT_REGEXP = /#{OPT_COMMENT_REGEXP}insert(?:\W+\w+)*?\W+into\W+`?([\w$]+)`?\.?`?([\w$]+)?/mi.freeze
      UPDATE_REGEXP = /#{OPT_COMMENT_REGEXP}update(?:\W+\w+)*?\W+([\w$]+)\W+set/mi.freeze
      DELETE_REGEXP = /#{OPT_COMMENT_REGEXP}delete(?:\W+\w+)*?\W+from\W+`?([\w$]+)`?\.?`?([\w$]+)?/mi.freeze
      REPLACE_REGEXP = /#{OPT_COMMENT_REGEXP}replace(?:\W+\w+)*?\W+into\W+`?([\w$]+)`?\.?`?([\w$]+)?/mi.freeze

      def self.call(sql, connection_info, time_span:, exception: nil, async: false, lock_wait: nil)
        return false if sql.nil?

        table = nil

        operation_key = case sql.b
        when SELECT_REGEXP
          table = $2 ? $2 : $1
          :select
        when UPDATE_REGEXP
          table = $1
          :update
        when INSERT_REGEXP
          table = $2 ? $2 : $1
          :insert
        when DELETE_REGEXP
          table = $2 ? $2 : $1
          :delete
        when REPLACE_REGEXP
          table = $2 ? $2 : $1
          :replace
        else
          return false
        end

        if table
          table.downcase!
        end

        record_stats(
          operation: operation_key,
          duration: time_span.duration,
          table: table,
          connection_info: connection_info,
          exception: exception,
          async:,
          lock_wait:,
          sql:,
        )

        true
      end

      def self.record_stats(operation:, duration:, connection_info:, table:, exception: nil, async: false, lock_wait: nil, sql: nil)
        connection_class = connection_info.connection_class
        rpc_operation = GitHub::DatadogTagsCache::SQL_OPERATIONS[operation]
        cluster_name = connection_class.respond_to?(:cluster_name) ? connection_class.cluster_name : :unknown
        cluster = GitHub::DatadogTagsCache::SQL_CLUSTER_NAMES[cluster_name] || "cluster:#{cluster_name}"
        connection_role = GitHub::DatadogTagsCache::SQL_CONNECTION_ROLES[connection_info.connection_role]
        catalog_service = "catalog_service:#{GitHub.context[:catalog_service] || "unknown"}"
        mysql_table = "mysql_table:#{table}" if table

        if exception
          exception_error_code = "exception_error_code:#{exception.error_code}" if exception.respond_to?(:error_code)
          exception_class = "exception_class:#{exception.class.name}"
          exception = "exception:true"
        end

        if exception
          tags = [cluster, connection_role]
          tags << mysql_table if mysql_table
          tags << exception_class if exception_class
          GitHub.dogstats.increment("rpc.mysql.count.errors", tags: tags)
        end

        if GitHub.context[:db_call_source_datadog_tags]
          tags = [cluster, connection_role, rpc_operation]
          tags << mysql_table if mysql_table

          GitHub.dogstats.distribution("rpc.mysql.extra_tags.dist.time", duration, tags: tags.dup + GitHub.context[:db_call_source_datadog_tags])
        end

        tags = [catalog_service, cluster, connection_role, rpc_operation]
        if mysql_table
          owning_domain = GitHub.packageowners.package_owner_for(table) || "unknown"
          calling_domain = GitHub::DomainIsolation.current_domain || "unknown"
          package = "package:#{owning_domain}"
          uses_domain = owning_domain == calling_domain && owning_domain != "unknown" ? "uses_domain:true" : "uses_domain:false"
          tags << mysql_table
          tags << package
          tags << uses_domain
        end
        GitHub.dogstats.distribution("rpc.mysql.dist.time", duration, tags: tags)

        if async
          catalog_service = "catalog_service:#{catalog_service_from(sql)}"
          tags = [catalog_service, cluster, connection_role, mysql_table]
          GitHub.dogstats.distribution("active_record.load_async.db_time.time", duration, tags: tags)
          GitHub.dogstats.distribution("active_record.load_async.lock_wait.time", lock_wait, tags: tags)
        end
      end

      def self.catalog_service_from(sql)
        sql.match(/.*catalog_service:(?<catalog_service>[A-Za-z_\/]+)/)[:catalog_service]
      end
    end
  end
end
