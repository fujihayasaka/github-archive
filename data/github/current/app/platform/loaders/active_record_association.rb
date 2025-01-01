# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    # This is a bit of a special loader. It doesn't return a promise for the
    # data it loads, rather it ensures that the given association is loaded on
    # the object you pass in. It also attempts to do this in batch.
    class ActiveRecordAssociation < Platform::Loader
      class AssociationNotPreloadedError < StandardError; end

      def self.load_all(object, association_names)
        Promise.all(
          association_names.map do |association_name|
            load(object, association_name)
          end,
        )
      end

      def self.load(object, association_name)
        association = object.association(association_name)
        self.for(association.reflection.active_record, association_name).load(object)
      end

      def initialize(klass, association_name)
        @association_name = association_name.to_sym
        @klass = klass
      end

      def load(record)
        association = record.association(@association_name)

        # If the association is already loaded, save time by returning a resolved promise.
        return Promise.resolve(association.target) if association.loaded?

        through_association_name = association.reflection.options[:through]

        # If this association is a :through association,
        # we need to make sure the intermediate associations are loaded first
        load_target = if through_association_name && !record.association(through_association_name).loaded?
          ActiveRecordAssociation.load(record, through_association_name).then { super }
        else
          super
        end

        load_target.then do |target|
          # It's possible `Preloader` preloaded this
          # association on another object id. If that's
          # the case, copy over the association to this record
          # also.
          association.target = target unless association.loaded?

          target
        end
      end

      def fetch(records)
        ::ActiveRecord::Associations::Preloader.new(records: records, associations: [@association_name]).call

        records.index_with do |record|
          record.association(@association_name).target
        end
      end

      def dog_tags
        ["model:#{@klass.name.underscore}"]
      end
    end
  end
end
