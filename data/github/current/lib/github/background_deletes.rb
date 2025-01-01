# typed: strict
# frozen_string_literal: true


module GitHub
  class BackgroundDeletes

    class BackgroundDeletesError < RuntimeError; end

    ID = T.type_alias { T.any(Integer, String) }

    class Options < T::Struct

      # Exempt this query from cross-shard-query linter rules
      const :cross_shard_query_exempted, T::Boolean, default: false
      # If the model should be destroyed instead of the association.
      const :inverse_relationship, T::Boolean, default: false
      # The polymorphic association enum integer
      const :polymorphic_type_value, T.nilable(Integer)
      # The polymorphic association model name
      const :polymorphic_class_name, T.nilable(String)
      # When the records are stored in a sharded table this can be set to the column name used for sharding (e.g. `:repository_id`)
      const :sharding_key, T.nilable(Symbol)
      # When the records are stored in a sharded table this can be set to the value of the sharded column (e.g. `42`)
      const :sharding_value, T.nilable(ID)

      sig { params(values: T::Hash[Symbol, T.untyped]).returns(Options) }
      def merge(values)
        self.class.from_hash(serialize.merge(values))
      end

      sig { params(values: T::Hash[Symbol, T.untyped]).returns(Options) }
      def self.from_hash(values)
        super(values.stringify_keys)
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def serialize
        super.symbolize_keys
      end
    end

    class DeletionMode < T::Enum
      enums do
        Delete = new
        Destroy = new
      end
    end

    # Only `Repository` supports `RepositorySoftDelete`
    class DeletionStage < T::Enum
      enums do
        RepositorySoftDelete = new # Record is marked as deleted
        Purge = new # Record is deleted from the database
      end
    end

    class Config < T::Struct

      const :model_name, String
      const :association, Symbol
      const :options, Options
      const :sharding_value_key, T.nilable(Symbol)
      const :deletion_mode, DeletionMode
      const :deletion_stage, DeletionStage, default: DeletionStage::Purge
      const :run_if, T.proc.params(parent_model: T.untyped).returns(T::Boolean), default: ->(_parent_model) { true }
    end

    @configs_by_parent = T.let({}, T::Hash[String, T::Array[Config]])

    sig { params(parent_model_name: String, config: Config).void }
    def self.push(parent_model_name, config)
      @configs_by_parent[parent_model_name] = [] if @configs_by_parent[parent_model_name].nil?
      T.must(@configs_by_parent[parent_model_name]) << config
    end

    sig { params(parent_model: ApplicationRecord::Base, deletion_stage: DeletionStage).void }
    def self.enqueue_jobs(parent_model, deletion_stage: DeletionStage::Purge)
      parent_model_name = T.must(parent_model.class.name)
      parent_model_id = parent_model.id

      configs = @configs_by_parent[parent_model_name]

      return if configs.nil?

      configs.each do |config|
        next unless config.run_if.call(parent_model)
        next unless config.deletion_stage == deletion_stage

        if config.options.sharding_key.present? && config.sharding_value_key.present?
          sharding_value = parent_model.send(T.must(config.sharding_value_key)) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        end

        next unless records_exist?(parent_model, config, sharding_value)

        case config.deletion_mode
        when DeletionMode::Destroy
          DestroyDependentRecordsJob
            .perform_later(
              config.model_name,
              parent_model_id,
              config.association,
              **config.options.merge({ sharding_value: }).serialize
            )
        when DeletionMode::Delete
          DeleteDependentRecordsJob
            .perform_later(
              config.model_name,
              parent_model_id,
              config.association,
              **config.options.merge({ sharding_value: }).serialize.except(:cross_shard_query_exempted)
            )
        end
      end
    end

    sig { params(model_name: String, association_name: Symbol, options: Options).returns(String) }
    def self.model_name_from_assocation(model_name, association_name, options)
      if options.polymorphic_class_name.present?
        options.polymorphic_class_name
      elsif options.polymorphic_type_value.present?
        model_name.constantize.send("#{association_name}_types").invert[options.polymorphic_type_value]
      else
        model_name.constantize.reflect_on_association(association_name).klass.name
      end
    end

    sig { params(parent_model: ApplicationRecord::Base, config: Config, sharding_value: T.nilable(ID)).returns(T::Boolean) }
    def self.records_exist?(parent_model, config, sharding_value)
      return true if config.options.inverse_relationship # TODO: Support inverse relationships

      # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
      if config.options.sharding_key.present? && config.sharding_value_key.present?
        parent_model.public_send(config.association).where(config.options.sharding_key => sharding_value).exists?
      elsif parent_model.public_send(config.association).respond_to?(:exists?)
        parent_model.public_send(config.association).exists?
      else
        # has_one associations
        parent_model.public_send(config.association).present?
      end
      # rubocop:enable GitHub/AvoidObjectSendWithDynamicMethod
    end
  end
end
