# typed: strict
# frozen_string_literal: true

module AzureEXP::Beta
  class LocalAssignmentService
    sig { params(participant: Participant, namespace: String).returns(T::Hash[String, AzureEXP::Beta::ParameterType]) }
    def self.parameters(participant:, namespace:)
      experiments = AzureEXP::Beta::LocalExperimentationConfig.config.experiments_in(namespace:)
      cache_keys = experiments.map { |experiment| assignment_cache_key(participant:, namespace:, experiment: experiment.name) }

      # We are trying to resolve experiment -> cached value -> parameter

      # variant to param map for each experiments
      # [{variant1 => param1, variant2 => param2},...]
      variant_parameters = experiments.map do |experiment|
        experiment.variants.reduce({}) do |map, variant|
          map[variant.name] = variant.parameters
          map
        end
      end

      # mget returns in order, including nil values. So the returned values are guaranteed to match experiments.
      variant_names = Feeds::KV.store.mget(cache_keys).value { [] }

      # Map the cached variant names to parameters for each experiments, filter out any nils
      parameters = variant_names.filter_map.with_index do |variant, i|
        variant_parameters.dig(i, variant)
      end

      parameters.reduce(&:merge) || {}
    end

    sig { params(participant: Participant, namespace: String, experiment: String, variant: String).void }
    def self.assign_variant(participant:, namespace:, experiment:, variant:)
      Feeds::KV.store.set(assignment_cache_key(participant:, namespace:, experiment:), variant)
    end

    sig { params(participant: Participant, namespace: String, experiment: String).returns(T.nilable(String)) }
    def self.assigned_variant(participant:, namespace:, experiment:)
      Feeds::KV.store.get(assignment_cache_key(participant:, namespace:, experiment:)).value { nil }
    end

    sig { params(participant: Participant, namespace: String, experiment: String).returns(String) }
    private_class_method def self.assignment_cache_key(participant:, namespace:, experiment:)
      "#{participant.randomization_id}:#{namespace}:#{experiment}"
    end
  end
end
