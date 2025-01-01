# typed: strict
# frozen_string_literal: true

module AzureEXP::Beta
  class AssignmentService
    extend T::Sig

    sig { params(participant: Participant).returns(T::Array[AzureEXP::Beta::Namespace]) }
    def self.assignment(participant)
      remote_assignment = AzureEXP::Beta::RemoteAssignmentService.assignment(participant)
      locally_configured_namespaces = AzureEXP::Beta::LocalExperimentationConfig.config.namespaces

      # look at every treatment in every experiment
      # and inspect the TAS Response to see whether the namespace/variants combination is satisfied
      namespaces = T.let([], T::Array[AzureEXP::Beta::Namespace])
      locally_configured_namespaces.each do |namespace|
        experiments = T.let([], T::Array[AzureEXP::Beta::Experiment])
        config = remote_assignment.configs.find { |config| config.id == namespace.name }

        namespace.experiments.each do |experiment|
          variants = T.let([], T::Array[AzureEXP::Beta::Variant])
          experiment.variants.each do |variant|
            is_locally_assigned = AzureEXP::Beta::LocalAssignmentService.assigned_variant(
              participant: participant,
              namespace: namespace.name,
              experiment: experiment.name
            ) == variant.name

            is_remotely_assigned = config.nil? ? false : variant.parameters.all? { |name, value| config.parameters[name] == value }

            assignment_state = if is_locally_assigned
              AzureEXP::Beta::AssignmentState::Local
            elsif is_remotely_assigned
              AzureEXP::Beta::AssignmentState::Remote
            else
              AzureEXP::Beta::AssignmentState::None
            end

            variant = AzureEXP::Beta::Variant.new(
              name: variant.name,
              parameters: variant.parameters,
              assignment_state: assignment_state,
              details: variant.details,
            )

            variants = variants.push(variant)
          end

          experiment = AzureEXP::Beta::Experiment.new(name: experiment.name, variants: variants)
          experiments = experiments.push(experiment)
        end

        namespace = AzureEXP::Beta::Namespace.new(name: namespace.name, experiments: experiments)
        namespaces = namespaces.push(namespace)
      end

      namespaces
    end
  end
end
