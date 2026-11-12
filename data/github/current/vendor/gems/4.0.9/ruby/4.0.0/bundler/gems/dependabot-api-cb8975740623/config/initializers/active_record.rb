# frozen_string_literal: true

module ActiveRecord
  module RelationExtensions
    DEPENDENT_DELETE_OPTIONS = %i(destroy delete destroy_async).freeze

    # Perform a cascading delete_all on the relation and all of its associations which would be
    # deleted via `dependent: :destroy`, `dependent: :delete`, or `dependent: :destroy_async`.
    # delete_all_with_dependents will be called recursively on each association level.
    #
    # Also deletes ActiveStorage::Blob records associated with the relation's records
    # through `has_one_attached` or `has_many_attached` ActiveStorage::Attachment associations.
    # Note that this does not purge the blobs from the storage service, so the files will still be
    # present in the storage service after this method is called. Please ensure that the storage
    # service is configured with its own data retention policy to clean up unreferenced files
    # after a reasonable amount of time.
    #
    # This method avoids loading records into memory by performing delete_all queries
    # on each association level, but does not run any ActiveRecord callbacks or validations.
    #
    # Returns the number of records deleted from the main relation, not including dependent deletes.
    def delete_all_with_dependents(batch_size: 1000)
      cascading_deletes = klass.reflect_on_all_associations.select do |association|
        next false unless DEPENDENT_DELETE_OPTIONS.include?(association.options[:dependent])

        association.foreign_key.present?
      end

      if cascading_deletes.any? || klass == ActiveStorage::Attachment
        in_batches(of: batch_size) do |batch|
          ids_to_delete = ids_for_relation(batch)
          next if ids_to_delete.empty?

          cascading_deletes.each do |association|
            scope = scope_for_association(association, ids_to_delete)
            scope.delete_all_with_dependents(batch_size: batch_size)
          end

          next unless klass == ActiveStorage::Attachment

          ActiveStorage::Blob.joins(:attachments).where(attachments: { id: ids_to_delete }).delete_all
        end
      end

      delete_all
    end

    private

    # Builds a scope for the given association and batch of records to delete, applying the association's
    # foreign key, type, and scope if present.
    def scope_for_association(association, foreign_keys_to_delete)
      scope = association.klass
      scope = scope.where(association.foreign_key => foreign_keys_to_delete)
      scope = scope.where(association.type => klass.polymorphic_name) if association.type
      scope = scope.instance_exec(&association.scope) if association.scope
      scope
    end

    # Returns the ids found for the given relation, preferring to pull ids from the relation's
    #  where_values_hash if possible to avoid an unnecessary query.
    def ids_for_relation(relation)
      return Array(relation.where_values_hash["id"]) if relation.where_values_hash.key?("id")

      relation.pluck(:id)
    end
  end
end

ActiveRecord::Relation.include ActiveRecord::RelationExtensions
