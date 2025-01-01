# typed: strict
# frozen_string_literal: true

module GH
  module Associations
    module BatchMethodAdapters
      extend T::Helpers
      include GitHub::BatchMethod

      sig { params(method_name: Symbol).returns(Symbol) }
      def self.internal_prelude_domain_method_name(method_name)
        "_#{method_name}_preloaded_via_domain".to_sym
      end

      module ClassMethods
        extend T::Helpers

        requires_ancestor { Kernel }

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def entity_reference_return_types
          @entity_reference_return_types ||= T.let({}, T.nilable(T::Hash[Symbol, T.untyped]))
        end

        # shorthand for #entity_reference that encapsulates common belongs_to foreign key patterns
        sig do
          params(
            name: Symbol,
            foreign_key: Symbol,
            return_type: T.untyped,
            ar_relation: T::Boolean,
            feature_flag: T.nilable(String),
            association_fetch_block: T.proc.params(foreign_keys: T::Array[Integer]).returns(T::Enumerable[T.untyped])
          ).void
        end
        def belongs_to_domain(name, foreign_key:, return_type:, ar_relation: false, feature_flag: nil, &association_fetch_block)
          block = proc do |records|
            foreign_keys = records.map(&foreign_key).compact
            next {} if foreign_keys.empty?

            associated_records = association_fetch_block.call(foreign_keys).group_by(&:id)
            records_hash = records.index_with do |record|
              associated_records[record.public_send(foreign_key)]&.first # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
            end

            records_hash
          end

          entity_reference(name, ar_relation:, feature_flag:, foreign_key:, return_type:, &block)
        end

        # This method exists to help migrate an existing ActiveRecord Association to a batched method that
        # preloads its data through a public domain interface method.
        # https://thehub.github.com/epd/engineering/products-and-services/dotcom/app-partitioning/domain-interface/
        #
        # class Gadget < ApplicationRecord
        #   belongs_to :gizmo
        #   entity_reference(:gizmo, ar_relation: true, feature_flag: "safely_deploy_gizmo_change") do |gadgets|
        #     gizmos = gizmo_domain.by_ids(ids: gadgets.map(&:gizmo_id)).index_by(&:id)
        #   end
        # end
        #
        # Keeping the original AR association in place allows pre-existing syntax to continue to work, e.g. Gadget.includes(:gizmo)
        #
        # See prelude docs for details on Prelude specific syntax https://github.com/seejohnrun/prelude/blob/main/README.md
        #
        # If you are adding a new relation to a model that has a domain interface, consider just adding it as a prelude
        # batch method directly and not adding the ActiveRecord association.
        sig do
          params(
            name: Symbol,
            return_type: T.untyped,
            foreign_key: T.nilable(Symbol),
            ar_relation: T::Boolean,
            feature_flag: T.nilable(String),
            prelude_block: T.proc.params(foreign_keys: T::Enumerable[T.untyped]).returns(T::Enumerable[T.untyped])
          ).void
        end
        def entity_reference(name, return_type:, foreign_key: nil, ar_relation: false, feature_flag: nil, &prelude_block)
          domain_fetch = GH::Associations::BatchMethodAdapters.internal_prelude_domain_method_name(name)

          block = if ar_relation
            proc do |*args|
              records_hash = prelude_block.call(*args)
              available_records = records_hash.values.flatten
              GitHub::PrefillAssociations.prefill_associations(records_hash.keys, name, available_records:) if available_records.any?
              records_hash
            end
          else
            prelude_block
          end

          entity_reference_return_types[name] = return_type

          T.bind(self, Prelude::Preloadable::ClassMethods)
          define_prelude(domain_fetch, &block)

          T.bind(self, Module).define_method(name) do
            if feature_flag && !GitHub.flipper[feature_flag].enabled?
              return super() if defined?(super)
            end

            if ar_relation
              T.bind(self, ActiveRecord::Base)
              # skip prelude preloading if AR already loaded this association
              return super() if association(name).loaded?
            end

            result = T.bind(self, ActiveRecord::Base).public_send(domain_fetch) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod

            if result.nil? && ar_relation
              association(name).target = result # rubocop:disable GitHub/DontCallAssociationTargetEquals
            end

            result || (super() if ar_relation)
          end

          define_method("async_#{name}") do
            if GitHub.flipper[:async_domain_assoc].enabled?
              Platform::Loaders::BelongsToDomainAdapter.load(self, domain_fetch, name)
            else
              super()
            end
          end
        end
      end

      mixes_in_class_methods(ClassMethods)
    end
  end
end
