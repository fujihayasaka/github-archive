# typed: strict
# frozen_string_literal: true

module GitHub
  # Extend this module to mark associations to be deleted or destroyed in the
  # background, rather than in-line as part of an ongoing transaction. Used to
  # prevent potential performance issues when deleting records with large
  # numbers of dependents.
  module BackgroundDependentDeletes
    extend T::Sig
    extend T::Helpers

    requires_ancestor { ApplicationRecord::Base }

    class BackgroundDependentDeleteError < RuntimeError; end

    # set to true if you want to skip queuing the jobs in the `after_commit` so
    # you can explicilty call `enqueue_background_dependent_jobs` instead.
    sig { returns(T.nilable(T::Boolean)) }
    attr_accessor :skip_background_dependent_enqueues

    # Manually enqueue the background records jobs. Pass in the record that was destroyed.
    sig { void }
    def enqueue_background_dependent_jobs
      T.bind(self, ApplicationRecord::Base)

      GitHub::BackgroundDeletes.enqueue_jobs(self)
    end

    module ClassMethods
      extend T::Sig
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
          run_if: T.proc.returns(T::Boolean),
        ).void
      end
      def delete_dependents_in_background(
        assoc,
        sharding_key: nil,
        sharding_value_key: nil,
        run_if: -> { true }
      )
        class_name = self.name

        after_commit on: :destroy, if: run_if do
          T.bind(self, ApplicationRecord::Base)
          # Ask the class that requested a background dependent delete
          # for information about the given association, and grab the
          # ActiveRecord model class from the result so that we can count
          # any callbacks that that model has defined that may run at destruction.
          assoc_class = self.class.reflect_on_association(assoc).klass
          if assoc_class._commit_callbacks.empty?
            commit_destroy_cbs = []
          else
            commit_destroy_cbs = assoc_class._commit_callbacks.select { |c| c.instance_variable_get(:@if).include?(:destroy) }
          end

          if assoc_class._destroy_callbacks.empty?
            after_destroy_cbs = []
          else
            after_destroy_cbs = assoc_class._destroy_callbacks
          end

          # A model that has any destructors should be destroyed, rather than deleted
          # to allow the callbacks to run.
          destroy_cbs = commit_destroy_cbs + after_destroy_cbs
          if destroy_cbs.length > 0
            error_msg = "#{assoc_class} has #{destroy_cbs.length} destructor callbacks, and should be destroyed not deleted."
            raise BackgroundDependentDeleteError, error_msg
          end
          sharding_value = send(sharding_value_key) unless sharding_value_key.nil?

          record_exists = if sharding_value_key.present?
            send(assoc).where(sharding_key => sharding_value).exists?
          elsif send(assoc).respond_to?(:exists?)
            send(assoc).exists?
          else
            send(assoc).present? # has_one associations
          end

          if record_exists
            DeleteDependentRecordsJob.perform_later(
              T.must(class_name),
              id,
              assoc,
              sharding_key:,
              sharding_value:
            )
          end
        end
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
          cross_shard_query_exempted: T::Boolean,
          run_if: T.proc.returns(T::Boolean),
        ).void
      end
      def destroy_dependents_in_background(
        assoc,
        sharding_key: nil,
        sharding_value_key: nil,
        cross_shard_query_exempted: false,
        run_if: -> { true }
      )
        class_name = self.name

        after_commit on: :destroy, if: run_if do
          T.bind(self, ApplicationRecord::Base)
          sharding_value = send(sharding_value_key) unless sharding_value_key.nil?

          record_exists = if sharding_value_key.present?
            send(assoc).where(sharding_key => sharding_value).exists?
          elsif send(assoc).respond_to?(:exists?)
            send(assoc).exists?
          else
            send(assoc).present? # has_one associations
          end

          if record_exists
            DestroyDependentRecordsJob.perform_later(
              class_name,
              id,
              assoc,
              sharding_key:,
              sharding_value:,
              cross_shard_query_exempted:
            )
          end
        end
      end

      # Declare this model to be destroyed in the background after parent is destroyed.
      #
      # association - Symbol name of an association record that will trigger the destroy
      sig do
        params(
          association: Symbol,
          sharding_key: T.nilable(Symbol),
          sharding_value_key: T.nilable(Symbol),
          cross_shard_query_exempted: T::Boolean,
          polymorphic_type_value: T.nilable(Integer),
          polymorphic_class_name: T.nilable(String),
          run_if: T.proc.params(parent_model: T.untyped).returns(T::Boolean),
        ).void
      end
      def destroy_in_background_with(
        association,
        sharding_key: nil,
        sharding_value_key: nil,
        cross_shard_query_exempted: false,
        polymorphic_type_value: nil,
        polymorphic_class_name: nil,
        run_if: ->(_parent_model) { true }
      )
        model_name = T.must(self.name)
        options = GitHub::BackgroundDeletes::Options.new(
          sharding_key:,
          sharding_value: nil,
          cross_shard_query_exempted:,
          polymorphic_type_value:,
          polymorphic_class_name:,
          inverse_relationship: true,
        )
        parent_model_name = GitHub::BackgroundDeletes.model_name_from_assocation(model_name, association, options)
        config = GitHub::BackgroundDeletes::Config.new(
          model_name:,
          association:,
          options:,
          run_if:,
          sharding_value_key:,
          deletion_mode: GitHub::BackgroundDeletes::DeletionMode::Destroy,
        )

        GitHub::BackgroundDeletes.push(parent_model_name, config)
      end

      sig do
        params(
          association: Symbol,
          sharding_key: T.nilable(Symbol),
          sharding_value_key: T.nilable(Symbol),
          polymorphic_type_value: T.nilable(Integer),
          polymorphic_class_name: T.nilable(String),
          run_if: T.proc.params(parent_model: T.untyped).returns(T::Boolean),
        ).void
      end
      def delete_in_background_with(
        association,
        sharding_key: nil,
        sharding_value_key: nil,
        polymorphic_type_value: nil,
        polymorphic_class_name: nil,
        run_if: ->(_parent_model) { true }
      )
        model_name = T.must(self.name)
        options = GitHub::BackgroundDeletes::Options.new(
          sharding_key:,
          sharding_value: nil,
          polymorphic_type_value:,
          polymorphic_class_name:,
          inverse_relationship: true,
        )

        parent_model_name = GitHub::BackgroundDeletes.model_name_from_assocation(model_name, association, options)
        config = GitHub::BackgroundDeletes::Config.new(
          model_name:,
          association:,
          options:,
          run_if:,
          sharding_value_key:,
          deletion_mode: GitHub::BackgroundDeletes::DeletionMode::Delete,
        )

        GitHub::BackgroundDeletes.push(parent_model_name, config)
      end
    end

    mixes_in_class_methods(ClassMethods)
  end
end
