# typed: true
# frozen_string_literal: true

# ES8-COMPATIBILITY
# TODO: Remove this entire file once the ES8 upgrade is complete
module Elastomer
  module UpgradeShims
    extend self
    # response["hits"]["total"] is an integer in ES5 and a hash in ES8+
    def get_total_hits(hits)
      hits["total"].is_a?(Hash) ? hits["total"]["value"] : hits["total"]
    end

    # Removes the _type field from the search response
    # In tests, the mocked search responses for ES8+ should not have a _type field
    # Also modifies the total hits field to be a hash with a "value" key to match the ES8+ response format
    def shim_search_response_hits(hits)
      hits["hits"].each do |hit|
        hit.delete("_type")
      end
      hits["total"] = { "value" => hits["total"], "relation" => "eq" }
      hits
    end

    # Add a `_meta` field to the mapping to store index metadata.
    #
    # If we are running on an ES8 cluster put the `_meta` field directly in the single document
    # type configured in the mapping.
    #
    # Otherwise, add it as a second document type alongside the one already defined in the mapping.
    def write_index_metadata(mappings, metadata_hash, cluster_running_version_8_plus: false)
      meta_field = { "_meta" => metadata_hash }
      unless cluster_running_version_8_plus
        meta_field = { Index::INDEX_META => meta_field }
      end
      mappings.merge(meta_field)
    end

    # Retrieves the `_meta` field from its new location in ES8 indexes,
    # which is within the mapping for a particular document type, or from the
    # INDEX_META type in ES5 indexes
    #
    # If we initially retrieve metadata from the cluster, we need to check for the
    # document type `_doc` in the response.
    # Otherwise, we are retrieving metadata from the mappings API, `_doc` will not be
    # in the response, and we need to check for the `_meta` field directly in the mappings.
    #
    # Input: hash - the hash starting at {"mappings": ...} key
    def read_index_metadata(hash)
      return Hash.new if hash.blank? || !hash.key?("mappings")

      mappings = hash["mappings"]
      mappings.dig(Index::INDEX_META, "_meta") || mappings.dig("_doc", "_meta") || mappings.dig("_meta") || Hash.new
    end
  end
end
