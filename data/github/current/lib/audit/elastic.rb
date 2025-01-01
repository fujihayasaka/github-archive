# typed: true
# frozen_string_literal: true

module Audit
  module Elastic
    autoload :Adapter, "audit/elastic/adapter"
    autoload :EntryRepair, "audit/elastic/entry_repair"
    autoload :Error, "audit/elastic/error"
    autoload :Hit, "audit/elastic/hit"
    autoload :Logger, "audit/elastic/logger"
    autoload :Migrator, "audit/elastic/migrator"
    autoload :Searcher, "audit/elastic/searcher"

    # Finds every audit log index name in a cluster with this process's
    # Elastomer postfix. This performs an Elasticsearch network RPC.
    #
    # Returns an array of Strings.
    def self.indices(cluster)
      results = cluster.indices.keys.select do |index|
        next unless index.starts_with?("audit_log")

        slicer = begin
          ::Elastomer::Slicers::AuditLogDateSlicer.new(fullname: index, postfix: Elastomer.env.postfix)
         rescue ArgumentError
           nil
        end

        # If slicer does not exist, this is not a valid audit log index name.
        next unless slicer.present?

        if Rails.env.test?
          # Audit log index names do not have a date slice in the test environment.
          true
        else
          slicer.slice.present?
        end
      end
      results.sort
    end

    # Public: Determine the index we want to track metrics under. Any query that
    # spans multiple indices will be grouped under audit_log.
    #
    # target - The String index name queried
    #
    # Examples
    #
    #  > Audit::Elastic.metric_index_name("audit_log-2015-01,audit_log-2016-01")
    #  => "audit_log"
    #
    #  > Audit::Elastic.metric_index_name("audit_log")
    #  => "audit_log"
    #
    #  > Audit::Elastic.metric_index_name("audit_log-2015-01")
    #  => "audit_log-2015-01"
    #
    # Returns String.
    def self.metric_index_name(index)
      if index =~ /\Aaudit_log\-.*,/
        "audit_log"
      else
        index
      end
    end
  end
end
