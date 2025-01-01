# typed: true
# frozen_string_literal: true

module Elastomer::Adapters
  class AuditEntry < Elastomer::Adapter
    # Internal: Ignore an explicit list of properties from being logged in the
    # data property inside Audit Log events.
    EXCLUDED_DATA_KEYS = %i[
      request_body
      spamurai_form_signals
      funcaptcha_session_id
      funcaptcha_solved
      funcaptcha_response
      hydro
    ].freeze

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "AuditLog"
    end

    # Public: Returns the database cluster name used to wait for replication
    # delay before indexing or deleting the adapter from Elasticsearch.
    def self.mysql_cluster
      :auditlogs
    end

    # Audit log entries are special in that they don't have a lookup id.
    def model=(model)
      case model
      when Audit::Elastic::Hit
        GitHub.dogstats.increment("audit_entry.id.existing")

        @model = model
        @document_id = model.id
      else
        @model = Audit::Elastic::Hit.new(model)

        if @model.key?("_document_id")
          GitHub.dogstats.increment("audit_entry.id.generated")
          @document_id = @model.delete("_document_id")
        else
          GitHub.dogstats.increment("audit_entry.id.fallback")
          @document_id = @model.id
        end
      end
    end

    # Public: The shard key we want to write the Audit Log entry to.
    #
    # Each Audit Log entry can have many types of keys that reference
    # organizations and users we have prioritized organization, actor, and user
    # in order.
    #
    # Returns String.
    def shard_key
      # There is a known case where org_id can be an Array of integers.
      # We're only looking for events where they are routed to a single organization.
      if @model[:org_id].is_a?(Integer)
        "Organization;#{@model[:org_id]}"
      else
        if (user_id = @model[:actor_id] || @model[:user_id]).present?
          "User;#{user_id}"
        else
          GitHub.dogstats.increment("audit_entry.shard_key.missing")
          "User;0"
        end
      end
    end

    # Public: Returns the value used to determine which index slice the document
    # data from this adapter should be written to. We return a Time value which
    # is the timestamp when the audit log entry was first created.
    def slice_value
      Audit.milliseconds_to_time(timestamp).utc
    end

    def params
      { op_type: "create" }
    end

    # Public: Construct a document suitable for indexing in ElasticSearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    #
    def to_hash
      if model.nil?
        raise Elastomer::ModelMissing, "The data model has not been set, or the document ID does not exist in the database."
      end

      return @hash if defined? @hash
      @hash = split_payload(model)
      @hash[:_id] = document_id.to_s unless document_id.nil?
      @hash[:_type] = document_type
      @hash[:@timestamp] = timestamp
      @hash
    end

    # Public: Splits non-indexed Audit payload data into a separate 'data'
    # key.
    #
    #   split_payload(:actor_id => 1, :foo => 'bar')
    #   # {:actor_id => 1, :data => {:foo => 'bar'}}
    #
    # Returns a Hash.
    def split_payload(payload)
      data = {}
      payload[:data] ||= {}
      # The keys may already be present in the :data key.
      payload[:data] = payload[:data].symbolize_keys.except(*EXCLUDED_DATA_KEYS)
      payload.each_key do |key|
        next if index_mapping.key?(key.to_sym)
        value = payload.delete(key)

        # We've already checked above for keys to exclude if they are in the
        # :data key, but if they're top level we need to exclude them here.
        unless EXCLUDED_DATA_KEYS.include?(key.to_sym)
          data[key] = value
        end
      end
      payload[:data].merge!(data)
      payload
    end

    def index_mapping
      @index_mapping ||= begin
        index = Elastomer.env.lookup_index(self)
        index.mappings_hook[document_type.to_sym][:properties]
      end
    end

    # Internal: Ensures that the `:@timestamp` field is in the proper units and
    # format - i.e. it is converted to UTC milliseconds since the epoch and
    # returned as an Integer.
    def timestamp
      @timestamp ||= Audit.time_to_milliseconds(model.get(:@timestamp) || Time.current)
    end
  end  # AuditLog
end  # Elastomer::Index
