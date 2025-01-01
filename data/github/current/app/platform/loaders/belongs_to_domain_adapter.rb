# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class BelongsToDomainAdapter < Platform::Loader
      def self.load(record, batch_method, association_name, *args)
        self.for(batch_method, association_name, args).load(record)
      end

      def initialize(batch_method, association_name, args)
        @batch_method = batch_method
        @association_name = association_name
        @args = args
        @prelude_platform_loader = Platform::Loaders::Prelude.for(batch_method, args)
      end

      def load(record)
        association = record.association(@association_name)
        # If the association is already loaded, save time by returning a resolved promise.
        return Promise.resolve(association.target) if association.loaded?

        super.then do |target|
          association.target = target unless association.loaded? # rubocop:disable GitHub/DontCallAssociationTargetEquals
          target
        end
      end

      def fetch(records)
        @prelude_platform_loader.fetch(records)
      end
    end
  end
end
