# typed: true
# frozen_string_literal: true

module Audit
  module Elastic
    require "ruby-progressbar"

    # Migrates documents between ElasticSearch clusters.
    #
    # source_cluster       - The cluster key for the Elasticsearch cluster to
    #                        migrate documents from.
    # source_name          - The name of the index to scan documents from.
    # destination_cluster  - The cluster key for the Elasticsearch cluster to
    #                        migrate documents to.
    # destination_name     - The name of the index you wish to create and move
    #                        the records into.
    #
    # Usage:
    #
    # migrator = Migrator.new({
    #   source_cluster: "auditlogsearch2",
    #   source_name: "audit_log-3-2013-01-1",
    #   destination_cluster: "auditlogsearch3",
    #   destination_name: "audit_log-4-2013-01-1",
    # })
    # migrator.test
    # migrator.run
    #
    class Migrator
      attr_reader :source_cluster
      attr_reader :source_client
      attr_reader :source_index
      attr_reader :source_name
      attr_reader :destination_cluster
      attr_reader :destination_client
      attr_reader :destination_index
      attr_reader :destination_name
      attr_accessor :verbose


      def initialize(source_cluster:, source_name:, destination_cluster:, destination_name:, verbose: false)
        @source_cluster = source_cluster
        @source_name = source_name
        @destination_cluster = destination_cluster
        @destination_name = destination_name
        @verbose = !!verbose
        @source_client = Elastomer.client(@source_cluster)
        @destination_client = Elastomer.client(@destination_cluster)
        @source_index = @source_client.index(@source_name)
        @destination_index = @destination_client.index(@destination_name)
      end

      def verbose?
        !!verbose
      end

      def source_url
        source_client.url
      end

      def destination_url
        destination_client.url
      end

      def source_count
        source_index.docs.count(q: "*")
      end

      def destination_count
        destination_index.docs.count(q: "*")
      end

      def create_destination_index
        return true if destination_index.exists?

        log "Destination index did not exist - creating it"
        destination_index.create(index: destination_index.name)
      end

      def test
        log "#{source_url}/#{source_name} --> #{destination_url}/#{destination_name}"

        create_destination_index

        results = { source: source_count, destination: destination_count }

        log "Source docs:      #{results[:source]["count"]}"
        log "Destination docs: #{results[:destination]["count"]}"

        results
      end

      def run
        log "Running ElasticSearch data migration"
        log "#{source_url}/#{source_name} --> #{destination_url}/#{destination_name}"

        unless Rails.env.test?
          progress = ProgressBar.create(title: destination_name, total: source_count["count"], format: "%t: |%B| %E")
        end

        bulk_options = {
          request_size: 25.megabytes,
          timeout: "30s",
        }
        scan_query = {
          query: {
            match_all: {},
          },
        }
        scan_options = {
          size: 2500,
        }

        response = destination_index.bulk(bulk_options) do |bulk|
          scan = source_index.scan(scan_query, scan_options)

          scan.each_document do |doc|
            progress.increment unless Rails.env.test?

            new_doc = doc["_source"]
            params = {}
            params["_id"] = doc["_id"]
            unless Elastomer.router.cluster_running_version_8_plus?(destination_cluster)
              params["_type"] = doc["_type"]
            end

            index_response = bulk.index(new_doc, params)

            # After the bulk operation submits the document in batches we need to
            # repair any entries that had errors.
            if index_response.present?
              repair_entries(index_response)
            end
          end
        end

        if response.present?
          repair_entries(response)
        end

        progress.finish unless Rails.env.test?
      end

      private

      def repair_entries(response)
        entry_repair = EntryRepair.new(response, source_index: source_index, destination_index: destination_index)

        if entry_repair.errors?
          log "Repairing #{entry_repair.length} of #{entry_repair.total_entries} audit log #{'entry'.pluralize(entry_repair.length)}"
          repaired, errored = entry_repair.perform
          log "#{repaired.length} repaired, #{errored.length} had errors"

          if verbose?
            errored.each do |entry_id, error|
              log "[#{entry_id}] #{error}"
            end
          end
        end
      end

      # Internal: Write a log message - send to STDOUT if not in test
      def log(message)
        Rails.logger.debug message
        return if Rails.env.test?
        puts "[#{Time.now.iso8601.sub(/-\d+:\d+$/, '')}] #{message}"
      end
    end
  end
end
