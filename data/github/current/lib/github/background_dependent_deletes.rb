# typed: strict
# frozen_string_literal: true

module GitHub
  # Extend this module to mark associations to be deleted or destroyed in the
  # background, rather than in-line as part of an ongoing transaction. Used to
  # prevent potential performance issues when deleting records with large
  # numbers of dependents.
  module BackgroundDependentDeletes
    extend T::Helpers

    requires_ancestor { ApplicationRecord::Base }

    class BackgroundDependentDeleteError < RuntimeError; end

    # set to true if you want to skip queuing the jobs in the `after_commit` so
    # you can explicilty call `enqueue_background_dependent_jobs` instead.
    sig { returns(T.nilable(T::Boolean)) }
    attr_accessor :skip_background_dependent_enqueues

    # Manually enqueue the background records jobs. Pass in the record that was destroyed.
    sig { params(deletion_stage: GitHub::BackgroundDeletes::DeletionStage).void }
    def enqueue_background_dependent_jobs(deletion_stage: GitHub::BackgroundDeletes::DeletionStage::Purge)
      T.bind(self, ApplicationRecord::Base)

      GitHub::BackgroundDeletes.enqueue_jobs(self, deletion_stage:)
    end

    module ClassMethods
      extend T::Helpers

      requires_ancestor { T.class_of(ApplicationRecord::Base) }

      sig { params(base: T.class_of(ApplicationRecord::Base)).void }
      def self.extended(base)
        base.after_commit on: :destroy, unless: :skip_background_dependent_enqueues do
          T.bind(self, ApplicationRecord::Base)

          self.enqueue_background_dependent_jobs
        end
      end

      # Declare this association to be deleted in the background.
      #
      # assoc - Symbol name of an association
      #
      # Sets an after_commit :on => destroy hook to queue a job which deletes the
      # dependent records from the database.
      sig do
        params(
          assoc: Symbol,
          sharding_key: T.nilable(Symbol),
          sharding_value_key: T.nilable(Symbol),
          parent_sharding_key: T.nilable(Symbol),
          parent_sharding_value_key: T.nilable(Symbol),
          deletion_stage: GitHub::BackgroundDeletes::DeletionStage,
          run_if: T.proc.params(parent_model: T.untyped).returns(T::Boolean),
        ).void
      end
      def delete_dependents_in_background(
        assoc,
        sharding_key: nil,
        sharding_value_key: nil,
        parent_sharding_key: nil,
        parent_sharding_value_key: nil,
        deletion_stage: GitHub::BackgroundDeletes::DeletionStage::Purge,
        run_if: ->(_parent_model) { true }
      )
        model_name = T.must(self.name)
        options = GitHub::BackgroundDeletes::Options.new(
          sharding_key:,
          parent_sharding_key:,
          inverse_relationship: false,
        )

        config = GitHub::BackgroundDeletes::Config.new(
          model_name:,
          association: assoc,
          options:,
          run_if:,
          sharding_value_key:,
          parent_sharding_value_key:,
          deletion_mode: GitHub::BackgroundDeletes::DeletionMode::Delete,
          deletion_stage:,
        )

        GitHub::BackgroundDeletes.push(model_name, config)
      end

      # Declare this association to be destroyed in the background.
      #
      # assoc - Symbol name of an association
      # cross_shard_query_exempted: if we should exempt this query from cross-shard-query linter rules
      #
      # Sets an after_commit :on => destroy hook to queue a job which destroys the
      # dependent records.
      sig do
        params(
          assoc: Symbol,
          sharding_key: T.nilable(Symbol),
          sharding_value_key: T.nilable(Symbol),
          parent_sharding_key: T.nilable(Symbol),
          parent_sharding_value_key: T.nilable(Symbol),
          cross_shard_query_exempted: T::Boolean,
          deletion_stage: GitHub::BackgroundDeletes::DeletionStage,
          run_if: T.proc.params(parent_model: T.untyped).returns(T::Boolean),
        ).void
      end
      def destroy_dependents_in_background(
        assoc,
        sharding_key: nil,
        sharding_value_key: nil,
        parent_sharding_key: nil,
        parent_sharding_value_key: nil,
        cross_shard_query_exempted: false,
        deletion_stage: GitHub::BackgroundDeletes::DeletionStage::Purge,
        run_if: ->(_parent_model) { true }
      )
        model_name = T.must(self.name)
        options = GitHub::BackgroundDeletes::Options.new(
          sharding_key:,
          parent_sharding_key:,
          cross_shard_query_exempted:,
          inverse_relationship: false,
        )
        config = GitHub::BackgroundDeletes::Config.new(
          model_name:,
          association: assoc,
          options:,
          run_if:,
          sharding_value_key:,
          parent_sharding_value_key:,
          deletion_mode: GitHub::BackgroundDeletes::DeletionMode::Destroy,
          deletion_stage:,
        )

        GitHub::BackgroundDeletes.push(model_name, config)
      end

      # Declare this model to be destroyed in the background after parent is destroyed.
      #
      # association - Symbol name of an association record that will trigger the destroy
      sig do
        params(
          association: Symbol,
          sharding_key: T.nilable(Symbol),
          sharding_value_key: T.nilable(Symbol),
          parent_sharding_key: T.nilable(Symbol),
          parent_sharding_value_key: T.nilable(Symbol),
          cross_shard_query_exempted: T::Boolean,
          polymorphic_type_value: T.nilable(Integer),
          polymorphic_class_name: T.nilable(String),
          deletion_stage: GitHub::BackgroundDeletes::DeletionStage,
          run_if: T.proc.params(parent_model: T.untyped).returns(T::Boolean),
        ).void
      end
      def destroy_in_background_with(
        association,
        sharding_key: nil,
        sharding_value_key: nil,
        parent_sharding_key: nil,
        parent_sharding_value_key: nil,
        cross_shard_query_exempted: false,
        polymorphic_type_value: nil,
        polymorphic_class_name: nil,
        deletion_stage: GitHub::BackgroundDeletes::DeletionStage::Purge,
        run_if: ->(_parent_model) { true }
      )
        model_name = T.must(self.name)
        options = GitHub::BackgroundDeletes::Options.new(
          sharding_key:,
          parent_sharding_key:,
          cross_shard_query_exempted:,
          polymorphic_type_value:,
          polymorphic_class_name:,
          inverse_relationship: true,
        )
        parent_model_name = GitHub::BackgroundDeletes.model_name_from_association(model_name, association, options)
        config = GitHub::BackgroundDeletes::Config.new(
          model_name:,
          association:,
          options:,
          run_if:,
          sharding_value_key:,
          parent_sharding_value_key:,
          deletion_mode: GitHub::BackgroundDeletes::DeletionMode::Destroy,
          deletion_stage:,
        )

        GitHub::BackgroundDeletes.push(parent_model_name, config)
      end

      sig do
        params(
          association: Symbol,
          sharding_key: T.nilable(Symbol),
          sharding_value_key: T.nilable(Symbol),
          parent_sharding_key: T.nilable(Symbol),
          parent_sharding_value_key: T.nilable(Symbol),
          polymorphic_type_value: T.nilable(Integer),
          polymorphic_class_name: T.nilable(String),
          deletion_stage: GitHub::BackgroundDeletes::DeletionStage,
          run_if: T.proc.params(parent_model: T.untyped).returns(T::Boolean),
        ).void
      end
      def delete_in_background_with(
        association,
        sharding_key: nil,
        sharding_value_key: nil,
        parent_sharding_key: nil,
        parent_sharding_value_key: nil,
        polymorphic_type_value: nil,
        polymorphic_class_name: nil,
        deletion_stage: GitHub::BackgroundDeletes::DeletionStage::Purge,
        run_if: ->(_parent_model) { true }
      )
        model_name = T.must(self.name)
        options = GitHub::BackgroundDeletes::Options.new(
          sharding_key:,
          parent_sharding_key:,
          polymorphic_type_value:,
          polymorphic_class_name:,
          inverse_relationship: true,
        )

        parent_model_name = GitHub::BackgroundDeletes.model_name_from_association(model_name, association, options)
        config = GitHub::BackgroundDeletes::Config.new(
          model_name:,
          association:,
          options:,
          run_if:,
          sharding_value_key:,
          parent_sharding_value_key:,
          deletion_mode: GitHub::BackgroundDeletes::DeletionMode::Delete,
          deletion_stage:,
        )

        GitHub::BackgroundDeletes.push(parent_model_name, config)
      end
    end

    mixes_in_class_methods(ClassMethods)
  end
end
