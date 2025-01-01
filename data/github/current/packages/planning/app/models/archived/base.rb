# typed: false
# frozen_string_literal: true

# Abstract base module for archive models. This adds some convenience methods,
# fixes up basic stuff like the default table name, and adds ::archive and
# #restore methods.
#
module Archived
  module Base
    extend ActiveSupport::Concern

    BATCH_SIZE = 50

    class_methods do
      # The name of the corresponding active table. Ex: if the archive model is
      # Archived::Project and the table is "archived_projects", this method returns
      # "projects".
      #
      # Returns the name of the table as a string.
      def active_table_name
        @active_table_name ||= table_name.sub(/^archived_/, "")
      end

      # The active model that corresponds to this archived model. Ex: if the archive
      # model is Archived::Project, this method returns the top-level Project class. Not
      # all archived models have corresponding active models because some are used
      # to model habtm relationships.
      #
      # Returns an AR model class or nil if no corresponding top-level class exists.
      def active_model_class
        class_name = to_s.split("::").last
        "::#{class_name}".constantize
      rescue NameError => boom
      end

      # In the Archived::Base test suite, there's a check where all archive model schemas
      # must match the active tables. This method serves as an override if there is a
      # reason the columns should mismatch.
      def columns_to_skip_schema_check
        []
      end

      def log_execution(record, action)
        GitHub.dogstats.distribution_time(
          "archived.dist.time",
          tags: ["action:#{action}", "model:#{record.class.name}"]
        ) do
          yield
        end
      end

      # Public: Archive a record and all associated records based on the association
      # information defined for the receiving class. This method is called on an
      # archived model and passed an instance of a corresponding normal model.
      #
      # record - The normal AR model instance to archive.
      # limit_per_query - The maximum number of rows to archive in a single query.
      #
      # Returns the newly created archive model instance.
      def archive(record, limit_per_query: BATCH_SIZE)
        if !record.is_a?(active_model_class)
          raise TypeError, "record #{record.class} must be a #{active_model_class}"
        end
        archive_record = nil
        self.log_execution(record, :archive) do
          reflect_on_has_associations.each do |association|
            next if !association.table_name.starts_with?("archived_")
            archive_model = association.class_name.constantize
            foreign_key = association.foreign_key
            scope = association.scope

            ids = association.options[:through] ? record.send(association.options[:through]).pluck(:id) : [record.id]
            archive_model.archive_table(ids, foreign_key, scope, record, limit_per_query: limit_per_query)
          end

          archive_table([record.id], :id, nil, record, limit_per_query: limit_per_query)
          archive_record = find(record.id)

          yield archive_record if block_given?

          unless record.destroy
            GitHub.dogstats.increment("archived", tags: ["action:archive", "error:bad_destroy"])
          end
        end
        archive_record
      end

      # Internal: Copy records from the model's active table to the corresponding
      # archive table.
      #
      # scope - Proc controlling which records are copied.
      # record - The record that is being archived, optionally passed to scope.
      # limit_per_query - The maximum number of rows to archive in a single query.
      #
      # Returns nothing.
      def archive_table(ids, key, scope, record, limit_per_query:)
        select_and_replace_records(self, active_model_class, ids, key, scope, record, limit_per_query: limit_per_query)
      end

      # Internal: Copy records from the model's archive table to the corresponding
      # active table.
      #
      # scope - Proc controlling which records are copied.
      # record - The record that is being archived, optionally passed to scope.
      # limit_per_query - The maximum number of rows to restore in a single query.
      #
      # Returns nothing.
      def restore_table(ids, key, scope, record, limit_per_query:)
        select_and_replace_records(active_model_class, self, ids, key, scope, record, limit_per_query: limit_per_query)
      end

      # Internal: Selects records from the original table and then replaces them into the new table.
      #
      # dest_model   - The model to move records to.
      # source_model - The model to move records from.
      # ids          - The ID's of the original table to select from.
      # key          - The key to select the ID's from (for example in a through association we need the
      #                foreign key, not the primary key)
      # scope        - Proc for additional control over what to select on. This is
      #                useful for polymorphic associations that need a type and an
      #                id to select on.
      # record       - The record that is being archived, optionally passed to scope.
      #
      # Returns nothing.
      def select_and_replace_records(dest_model, source_model, ids, key, scope, record, limit_per_query: BATCH_SIZE)
        while ids.present?
          ids_slice = ids.shift(limit_per_query)
          keyed_ids_slice = { key => ids_slice }

          association_scope = source_model.where(keyed_ids_slice)
          if scope
            if scope.arity == 1 # if the scope requires the original record as an argument
              association_scope = association_scope.instance_exec(record, &scope)
            else
              association_scope = association_scope.instance_exec(&scope)
            end
          end

          next if association_scope.blank?

          association_ids = association_scope.pluck(:id)

          replace_records_into(dest_model, source_model, association_ids, limit_per_query: limit_per_query)

          # If we are restoring a Storage::Uploadable model, all we need to do is re-create
          # the references and the `Storage::Purge`s will simple NOOP when their times come.
          if dest_model.try(:act_on_storage_uploadable?)
            uploadables = dest_model.where(keyed_ids_slice)
            GitHub::Storage::Creator.create_uploadable_references(uploadables) if uploadables.any?
          end
        end
      end

      # Internal: Determine whether a given model corresponds to a sharded
      # table, which then requires a different replacement strategy.
      #
      # model - The model to check for sharding.
      #
      # Returns boolean.
      def sharded_table?(model)
        # Right now, the only sharded tables that are archiveable inherit from
        # this "IssuesPullRequests" class.
        model.superclass.name.include? "IssuesPullRequests"
      end

      # Internal: Replaces records from the original table into the new table.
      #
      # For example if `archive` is called on Repository it's `issue_events` association
      # will be replaced into `archived_issue_events.
      #
      # If `restore` is called, `archived_issue_events` for that Repository will be replaced
      # into `issue_events`.
      #
      # dest_model   - The model to move records to.
      # source_model - The model to move records from.
      # ids          - The ID's collected in the select_records_from method.
      #
      # Returns nothing.
      def replace_records_into(dest_model, source_model, ids, limit_per_query: BATCH_SIZE)
        tries ||= 2

        # Reassign the ids so that if the while loop throws an exception the query can
        # start over with the original list of ids, otherwise the list will be empty.
        selected_ids = []
        selected_ids << ids
        selected_ids = selected_ids.flatten!

        while selected_ids.present?
          ids_slice = selected_ids.shift(limit_per_query)
          dest_cols = dest_model.columns.select { |c| !c.virtual? }.map { |col| col.name }

          if sharded_table?(dest_model)
            next replace_records_into_sharded_table(
              dest_model,
              source_model,
              dest_cols,
              ids_slice)
          end

          source_cols = source_model.columns.map { |col| col.name }
          source_table_name = quote_name(source_model.table_name)
          source_id_column = "#{source_table_name}.#{quote_name("id")}"
          cols = (source_cols & dest_cols).map { |name| quote_name(name) }.join(", ")

          sql = "REPLACE INTO #{quote_name(dest_model.table_name)} (#{cols}) " +
            "SELECT #{cols} FROM #{source_table_name} " +
            "WHERE #{source_id_column} IN (#{ids_slice.join(", ")}) "

          dest_model.throttle { connection.insert(sql) }
        end
      rescue ActiveRecord::StatementInvalid => e
        raise(e) unless e.message.include?("Unknown column")
        raise(e) if (tries -= 1).zero?

        # Let Failbot know this happened
        Failbot.report(e)

        # Reset all cached information about columns
        source_model.reset_column_information
        dest_model.reset_column_information

        # Try copying to the archive table again
        retry
      end

      # Internal: Replicates record replacement functionality from
      # replace_records_into, but for sharded tables (for which `REPLACE INTO` is not supported)
      #
      # dest_model   - The model to move records to.
      # source_model - The model to move records from.
      # dest_cols    - The set of target columns in the destination model to match to source columns
      # ids_slice    - The batch of ids to operate on.
      #
      # Returns nothing.
      def replace_records_into_sharded_table(dest_model, source_model, dest_cols, ids_slice)
        records = source_model.where(id: ids_slice)

        all_attributes = records.map(&:attributes_before_type_cast)

        select_values = all_attributes.map { |att| att.select { |key| dest_cols.include?(key) } }

        connection.transaction do
          dest_model.where(id: ids_slice).delete_all
          dest_model.insert_all!(select_values)
        end
      end

      # Internal: Quote a database column or table name.
      def quote_name(name)
        connection.quote_column_name(name)
      end

      # Internal: Only reflect on the has_* associations.
      def reflect_on_has_associations
        reflect_on_all_associations(:has_many) + reflect_on_all_associations(:has_one)
      end
    end

    included do
      self.table_name = self.name.gsub("::", "").underscore.downcase.pluralize

      delegate :quote_name, :quote_value, to: "self.class"
    end

    # Public: Restore an archived record and all associated records based on the
    # association information defined for the receiving object and destroy the
    # archive record and all associated archived records in other tables. The
    # entire restore operation runs within a transaction.

    # limit_per_query - The maximum number of rows to restore in a single query.
    #
    # Returns the newly restored model object.
    def restore(limit_per_query: BATCH_SIZE)
      record = nil
      self.class.log_execution(self, :restore) do
        self.class.restore_table([id], :id, nil, self, limit_per_query: limit_per_query)

        self.class.reflect_on_has_associations.each do |association|
          next if !association.table_name.starts_with?("archived_")
          archive_model = association.class_name.constantize
          foreign_key = association.foreign_key
          scope = association.scope

          ids = association.options[:through] ? self.send(association.options[:through]).pluck(:id) : [id]
          archive_model.restore_table(ids, foreign_key, scope, self, limit_per_query: limit_per_query)
        end

        record = self.class.active_model_class.find(id)
        yield record if block_given?

        unless destroy
          GitHub.dogstats.increment("archived", tags: ["action:restore", "error:bad_destroy"])
        end
      end
      record
    end
  end
end
