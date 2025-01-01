# typed: false
# frozen_string_literal: true

module Elastomer::Adapters

  # This is a suitable superclass for writing an adapter that needs to iterate
  # over some "items" that belong to a repository, and then reconcile the
  # state of those items between the database and the search index. A good
  # example would be the colleciton of Issues that belong to a repository.
  class RepositoryItemReconciler < ::Elastomer::Adapter

    attr_reader :add, :update, :remove
    alias :add? :add
    alias :update? :update
    alias :remove? :remove

    undef :document_routing
    alias :document_routing :document_id

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents. This adapter is not intended to be used directly,
    # so we return `nil` for the Index class name.
    def self.index_name
      nil
    end

    def self.mysql_cluster
      ::Repository.cluster_name
    end

    # Configure the adapter with the 'add', 'update', and 'remove' options.
    # These control which reconcile aspects are performed.
    def initialize(*args)
      super(*args)

      @add    = options.fetch("add",    true)
      @update = options.fetch("update", true)
      @remove = options.fetch("remove", true)
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    def model
      @model ||= ::Repositories.domain.by_id(document_id)
    end
    alias :repo :model

    # Public: Get or set the field names used to reconcile state between the
    # database and the search index. The values in these fields are used to
    # find items that are out of sync.
    #
    # value - The Array of fields names to use when reconciling state.
    #
    # Returns the Array of reconcile field names.
    def reconcile_fields(value = nil)
      if value.nil?
        @reconcile_fields
      else
        @reconcile_fields = Array(value)
      end
    end

    # Internal: This method will iterate over all the items for the current
    # repository and yield indexing actions. If an item needs to be updated
    # in the search index, then a [:index, {...}] action will be yielded. If
    # an item needs to be removed from the search index, then a [:delete, {...}]
    # action will be yielded.
    #
    # type - The item type as a String
    # opts - The options Hash
    #   :sql_conditions - optional conditions for restricting the SQL query
    #
    # Returns the Array of item IDs to add, update, and remove from the search index.
    def reconcile(type, opts = {}, &block)
      if repo.nil?
        raise Elastomer::ModelMissing, "The data model has not been set, or the document ID does not exist in the database."
      end

      ar_class = type.classify.constantize
      adapter_class = ::Elastomer.env.lookup_adapter(type)
      add, update, remove = generate_actions(type, opts)
      index_me = []

      if add? && !add.empty?
        GitHub.dogstats.count("search.reconcile.add", add.size, tags: datadog_tags(index, add_index_name_tag: true))
        index_me.concat add
      end

      if update? && !update.empty?
        GitHub.dogstats.count("search.reconcile.update", update.size, tags: datadog_tags(index, add_index_name_tag: true))
        index_me.concat update
      end

      index_me.each_slice(1_000) do |ids|
        ar_class.where(id: ids).each do |ar| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          # releases do not have a spammy? method
          if ar.respond_to?(:spammy?) && ar.spammy?
            remove << ar.id
          else
            begin
              adapter = adapter_class.create(ar, opts.slice(:skip_commit_info_on_failure))
              doc = adapter.to_hash
              block.call(:index, doc) if doc
            rescue => e
              Failbot.report(e)
            end
          end
        end
      end

      if remove?
        GitHub.dogstats.count("search.reconcile.remove", remove.size, tags: datadog_tags(index, add_index_name_tag: true)) unless remove.empty?
        remove.each { |id| block.call(:delete, { _id: id, _type: type, _routing: document_routing }) }
      end

      [add, update, remove]  # returning these for debugging purposes
    end

    # Internal: Lookup up the item states from the DB and from the search
    # index, and then generate three "action arrays". The first Array contains
    # all the IDs that need to be added to the search index. The second Array
    # contains all the IDs that need to be updated in the search index. And
    # the third Array contains all the IDs that need to be removed from the
    # search index.
    #
    # type - The item type as a String
    # opts - The options Hash
    #   :sql_conditions - optional conditions for restricting the SQL query
    #
    # Returns the Array of item IDs to add, update, and remove from the search index.
    def generate_actions(type, opts)
      db_hash = lookup_from_db(type, opts)
      es_hash = lookup_from_es(type, opts)

      db_keys = db_hash.keys
      es_keys = es_hash.keys

      add    = db_keys - es_keys
      remove = es_keys - db_keys

      update = []
      (db_keys & es_keys).each do |key|
        update << key if db_hash[key] != es_hash[key]
      end

      [add, update, remove]
    end

    # Internal: For the repository, read all the items and their
    # `reconcile_fields` from the database. A single Hash is returned that is
    # keyed by the item ID, and the values are the `reconcile_fields` for each
    # item.
    #
    # type - The item type as a String
    # opts - The options Hash
    #   :sql_conditions - optional conditions for restricting the SQL query
    #
    # Returns a Hash of ID / `reconcile_fields` pairs.
    def lookup_from_db(type, opts)
      ar_class = type.classify.constantize
      sanitized_id = ar_class.connection.quote(repo.id)
      query = item_query(ar_class.table_name, sanitized_id)
      query << " AND #{opts[:sql_conditions]}" if opts[:sql_conditions]

      hash = Hash.new
      ary = ar_class.connection.select_rows(query) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      ary.each do |id, *args|
        args.unshift repo.public
        hash[id] = args
      end
      hash
    end

    def item_query(table, repo_id)
      "SELECT id,#{reconcile_fields.join(',')} FROM #{table} WHERE repository_id = #{repo_id}"
    end

    # Internal: For the repository, read all the items and their
    # `reconcile_fields` from the search index. A single Hash is returned that
    # is keyed by the item ID, and the values are the `reconcile_fields` for
    # each item.
    #
    # type - The item type as a String
    # opts - The options Hash
    #
    # Returns a Hash of ID / `reconcile_fields` pairs.
    def lookup_from_es(type, opts)
      query = {
        query: { term: { repo_id: repo.id } },
        _source: reconcile_fields,
        size: 200,
      }
      scan = index.scan(query, type: type)

      hash = Hash.new
      scan.each_document do |doc|
        id = doc["_id"].to_i
        source = doc["_source"]

        if source.blank?
          hash[id] = nil
          next
        end

        ary = reconcile_fields.map do |name|
          val = source[name]
          val = Time.parse(val) if val && name =~ /_at\Z/i
          val
        end
        hash[id] = (ary.length == 1 ? ary.first : ary)
      end

      hash
    end

  end
end
