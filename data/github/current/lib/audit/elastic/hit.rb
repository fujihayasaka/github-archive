# typed: true
# frozen_string_literal: true

module Audit
  module Elastic
    class Hit < ActiveSupport::HashWithIndifferentAccess
      class UnknownCurrentActorError < StandardError; end
      class DisallowedFieldAccessError < StandardError; end

      include GitHub::Relay::GlobalIdentification

      # Used to identify Driftwood Global ID's.
      DRIFTWOOD_IDENTIFIER = "dw".freeze

      # Extra keys to keep at the top level of entry data when nesting.
      DRIFTWOOD_TOP_LEVEL_KEYS = %w[tie_breaker_id _document_id].freeze

      # Public: Look up an individual audit log entry from a specific audit log index.
      #
      # id         - The String document id to look up.
      # index      - The Elastomer::Indexes::AuditLog index to look for the document.
      # type:      - The String document type to lookup (default: 'audit_entry').
      #
      # Examples
      #
      #   @index = Elastomer::Indexes::AuditLog.new("audit_log-2014-06")
      #
      #   find("2M9hQOLZQFuN5TmD95lPag", @index)
      #   find("2M9hQOLZQFuN5TmD95lPag", @index, type: "audit_entry_redux")
      #
      # Returns Audit::Elastic::Hit instance
      def self.find(id, index, type: nil)
        type   ||= Elastomer::Adapters::AuditEntry.document_type
        document = index.docs.get(type: type, id: id)

        if document["found"] || document["exists"] # exists is removed in 1.2.x
          hit = new(document)
          hit.after_initialize
          hit
        end
      end

      # Public: Store an audit entry to a specific audit log index.
      #
      # id         - The String document id to save the entry to.
      # index      - The Elastomer::Indexes::AuditLog index to store the document in.
      # entry      - The Hash source for audit entry.
      #
      # Examples
      #
      #   @index = Elastomer::Indexes::AuditLog.new("audit_log-2014-06")
      #   @source = { :user => "dewski" }
      #
      #   store("2M9hQOLZQFuN5TmD95lPag", @index, @source)
      #
      # Returns raw Hash response from ElasticSearch
      def self.store(id:, index:, entry:, type: nil)
        audit_entry = Elastomer::Adapters::AuditEntry.create(entry)
        type      ||= Elastomer::Adapters::AuditEntry.document_type
        index.docs.index(audit_entry.to_hash, id: id, type: type)
      end

      # Private: Remaps user, actor, and org to local ids if they exist.
      #
      # attributes - Hash source from ElasticSearch hit
      #
      # Returns Hash
      def self.remap_entities(source)
        if user = User.find_by_login(source["user"])
          source["user_id"] = user.id
        end

        if actor = User.find_by_login(source["actor"])
          source["actor_id"] = actor.id
        end

        if org = Organization.find_by_login(source["org"])
          source["org_id"] = if source["org_id"].respond_to?(:each)
            source["org_id"] << org.id
          else
            org.id
          end
        end

        source
      end
      private_class_method :remap_entities

      attr_reader :id
      attr_reader :index
      attr_reader :index_name
      attr_reader :type
      attr_accessor :allowed_fields

      # Interface for interacting with ElasticSearch hits.
      #
      # Returns Audit::Elastic::Hit instance.
      def initialize(hit)
        @allowed_fields = []

        # accessing these fields is always permissable
        @always_allowed_fields = %w[_source action data raw_data tie_breaker_id]

        @hit = (hit || {}).with_indifferent_access

        if @hit["tie_breaker_id"] && @hit["_document_id"] # Driftwood result
          @driftwood_result = true
          @id = @hit["_document_id"]
          @type = Elastomer::Adapters::AuditEntry.document_type
          super(@hit)
        elsif @hit["_source"] # ElasticSearch result
          @id = @hit["_id"]
          @type =
            if Elastomer.router.cluster_running_version_8_plus?(GitHub.es_audit_log_cluster)
              Elastomer::Adapters::AuditEntry.document_type
            else
              @hit["_type"]
            end
          @index_name = @hit["_index"]
          @index = Elastomer::Indexes::AuditLog.new(@index_name)
          super(@hit["_source"])
        else # Manually initialized or malformed result
          @id = SecureRandom.urlsafe_base64(16)
          @type = Elastomer::Adapters::AuditEntry.document_type
          super(@hit)
        end
      end

      # Is this Hit from Driftwood or ElasticSearch?
      def driftwood_result?
        @driftwood_result || false
      end

      # Causes SystemStackError error since class is already HashWithIndifferentAccess
      def with_indifferent_access
        self
      end

      # index - The index to store the audit entry (optional).
      #
      # Returns true if saved, false if not.
      def save
        return false if driftwood_result? # Do not attempt save DW entries in ES.
        self.class.store(id: @id, index: @index, entry: self)
      end

      # Public: Takes the data field and stores it into the raw_data field which
      # is unindexed and unsearchable.
      #
      # `raw_data` expects a JSON string.
      #
      # Returns String.
      def repair_data
        self["raw_data"] = GitHub::JSON.encode(delete("data"))
      end

      # Public: Takes the actor's location and repairs the `lat` and `lon` to not be nil.
      #
      # Returns Hash
      def repair_location
        self["actor_location"] ||= {}
        self["actor_location"]["location"] ||= {}
        self["actor_location"]["location"]["lat"] ||= 0.0
        self["actor_location"]["location"]["lon"] ||= 0.0
      end

      # Public: Returns the path for the ES document
      #
      # Returns String
      def path
        if Elastomer.router.cluster_running_version_8_plus?(GitHub.es_audit_log_cluster)
          "/#{@index_name}/_doc/#{@id}"
        else
          "/#{@index_name}/#{@type}/#{@id}"
        end
      end

      # Public: Marks an audit entry as invalid. Invalid entries
      # will not be shown to users but will still show up in Stafftools.
      #
      # reason - The string reason for why the audit entry should not be shown to users.
      #
      # Returns a boolean representing if the update was successful.
      def invalidate(reason)
        actor = Audit.context[:actor].try(:to_s)
        raise UnknownCurrentActorError unless actor

        (self["data"] ||= {}).merge!({
          "_invalid" => true,
          "_invalid_actor" => actor,
          "_invalid_reason" => reason,
          "_invalid_at" => (Time.now.utc.to_f * 1000).round,
        })

        save
      end

      # Public: GraphQL Relay compatible global ID generation.
      #
      # Returns a String of global ID parts joined by a semi-colon (;).
      def global_id
        if driftwood_result?
          slice = slicer.slice_from_value(self["@timestamp"])
          [document_id, slice, DRIFTWOOD_IDENTIFIER].join(";")
        else
          slice = slicer.validate_fullname(index_name)[2]
          [document_id, slice].join(";")
        end
      end

      # Public: The GraphQL platform object type name. Used to determine which
      # GraphQL type to use when returning results. Types are keyed to event
      # action names.
      #
      # Returns a String representing a Ruby Class.
      def platform_type_name
        "#{action.tr(".", "_").camelize}AuditEntry"
      end

      def document
        self
      end

      def document_id
        @id
      end

      def action
        self["action"]
      end

      def created_at
        Audit.milliseconds_to_time(self["@timestamp"])
      end

      def [](key)
        unless @always_allowed_fields.include?(key.to_s)
          # if the allowed_fields array is empty then we assume that we are disabling enforcement entirely.
          unless @allowed_fields.empty?
            # otherwise a field has to exist in the allowed_fields list to be accessible
            unless @allowed_fields.include?(key.to_s)
              raise DisallowedFieldAccessError.new("Disallowed field access in action `#{action}` for field `#{key}`")
            end
          end
        end
        super(key.to_s) || dig("data", key.to_s)
      end

      def get(key)
        self[key.to_s] || dig("data", key.to_s)
      end

      # Public: Determines if the given key is present in the Audit Entry document.
      #
      # key - String key name.
      #
      # Returns true if key is present, false otherwise.
      def key?(key)
        return true if super(key.to_s)
        return true if dig("data", key.to_s).present?
        false
      end

      # Public: Transforms `created_at` field to a readable timestamp string.
      #
      # Returns a Hit.
      def with_human_timestamp
        self["created_at"] = Time.at(self["created_at"] / 1000).to_s
        self
      end

      # Public: Accessor to the data Hash in this Hit, used extensively throughout
      # Audit Log views and the AuditLogEntryView view model.
      #
      # Returns a Hash.
      def data
        self["data"] || {}
      end

      # Public: Called to do post initialization data transformations and clean up.
      # Modifies self.
      #
      # Returns nothing.
      def after_initialize
        load_repaired_data!
        rewrite_actions!
        rewrite_staff_user_fields!
      end

      # Public: Moves any keys that are not explicitly included in the included_mapping_keys
      # array to a nested "data" Hash, removing any keys in excluded_mapping_keys. This is used
      # to modify Driftwood results to match existing ElasticSearch results when reading from
      # Driftwood.
      #
      # Returns nothing.
      def nest_payload!
        clean_data = (self["data"] || {}).symbolize_keys.except(*excluded_mapping_keys)

        self.each_key do |key|
          next if included_mapping_keys.include?(key.to_sym)
          value = self.delete(key)
          clean_data[key] = value unless excluded_mapping_keys.include?(key.to_sym)
        end

        self["data"] = clean_data
      end

      private


      # Private: Takes the raw_data field if present and merges it into the
      # existing data field. Any values in the data field take precedence over
      # raw_data.
      #
      # Returns nothing.
      def load_repaired_data!
        if self["raw_data"].present?
          self["data"] ||= {}
          raw_data = GitHub::JSON.decode(delete("raw_data"))
          self["data"] = raw_data.merge(self["data"])
        end
      end

      # Private: Rewrite specific actions based on data present in the event.
      #
      # Returns nothing.
      def rewrite_actions!
        if self["action"] == "team.create" && self["from"] == "orgs/team_members#create"
          self["action"] = "team.add_member"
        elsif self["action"] == "team.delete" && ["orgs/teams#leave", "orgs/team_members#destroy"].include?(self["from"])
          self["action"] = "team.remove_member"
        elsif self["action"] == "team.create" && self["repo_id"].present?
          self["action"] = "team.add_repository"
        elsif self["action"] == "team.delete" && self["repo_id"].present?
          self["action"] = "team.remove_repository"
        end
      end

      # Private: Sanitize user fields if staff_actor fields exist with the same
      # values.
      #
      # Returns nothing.
      def rewrite_staff_user_fields!
        if GitHub.guard_audit_log_staff_actor?
          if self["staff_actor"].present? && self["staff_actor"] == self["user"]
            self["user"] = User.staff_user.login
          end

          if self["staff_actor_id"].present? && self["staff_actor_id"] == self["user_id"]
            self["user_id"] = User.staff_user.id
          end
        end
      end

      # Private: Audit Log index slicer accessor.
      def slicer
        Elastomer::Indexes::AuditLog.slicer
      end

      # Private: Keys that should be included at the top-level of Audit Log events.
      # Any fields outside of these will be moved to the nested data object by the
      # nest_payload! method.
      #
      # Returns an Array of field names.
      def included_mapping_keys
        @index_mapping ||= begin
          mapping = ::Elastomer::Indexes::AuditLog.mappings_hook.dig(:audit_entry, :properties).keys
          mapping.concat(DRIFTWOOD_TOP_LEVEL_KEYS)
          mapping
        end
      end

      # Private: Keys that should be removed completely from Audit Log events.
      #
      # Returns an Array of field names.
      def excluded_mapping_keys
        ::Elastomer::Adapters::AuditEntry::EXCLUDED_DATA_KEYS
      end
    end
  end
end
