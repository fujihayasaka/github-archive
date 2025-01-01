# typed: true
# frozen_string_literal: true

module Audit
  module Elastic
    class EntryRepair
      # Public: Handles repairing any entries that could not be migrated in a
      # Audit::Elastic::Migrator operation. Currently supports:
      #
      #   IllegalArgumentException - Value exceeds 32k
      #   MapperParsingException   - Destination index expected different type of value.
      #
      # Each entry will then store its `data` field to a non-indexed `raw_data` field.
      #
      # Arguments:
      #
      # response          - ElastomerClient::Client::Bulk response Hash
      # source_index      - Elastomer::Indexes::AuditLog where the documents
      #                     with errors are currently stored.
      # destination_index - Elastomer::Indexes::AuditLog instance where the repaired
      #                     documents will be stored.
      #
      # Returns Audit::Elastic::EntryRepair instance
      def initialize(response, source_index:, destination_index:)
        @response          = response
        @source_index      = source_index
        @destination_index = destination_index
      end

      def items_to_repair
        @items_to_repair ||= {}.tap do |loaded_items|
          @response["items"].each do |item|
            doc = item["index"]
            next if doc["error"].nil?

            hit = Audit::Elastic::Hit.find(doc["_id"], @source_index, type: doc["_type"])

            loaded_items[hit] = doc["error"]
          end
        end
      end

      # Public: Performs a data conversion of the erroring entries and saves
      # them to the destination index.
      #
      # Returns [repaired, errored] Array of documents that were repaired or
      # couldn't be repaired, false if there are no documents to repair.
      def perform
        return false unless errors?

        repaired_items = []
        errored_items = []

        items_to_repair.each do |hit, error|
          case error
          when /\AIllegalArgumentException/
            hit.repair_data
          when /\AMapperParsingException\[failed to parse\]; nested: ElasticsearchParseException\[(latitude|longitude) must be a number\];/
            hit.repair_location
          when /\AMapperParsingException/
            hit.repair_data
          end

          begin
            stored = Audit::Elastic::Hit.store(id: hit.id, index: @destination_index, entry: hit)
            if stored
              repaired_items << hit.id
            end
          rescue ElastomerClient::Client::Error
            errored_items << [hit.id, error]
          end
        end

        [repaired_items, errored_items]
      end

      def length
        items_to_repair.length
      end

      def total_entries
        @response["items"].length
      end

      # Public: Determine if there are any entries in
      # the response that errored during indexing.
      def errors?
        !!@response["errors"]
      end
    end
  end
end
