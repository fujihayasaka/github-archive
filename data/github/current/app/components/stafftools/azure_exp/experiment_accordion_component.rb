# typed: true
# frozen_string_literal: true

class Stafftools::AzureExp::ExperimentAccordionComponent < ApplicationComponent
  extend T::Sig

  attr_reader :namespace, :experiment, :editable

  sig { params(namespace: AzureEXP::Beta::Namespace, experiment: AzureEXP::Beta::Experiment, editable: T::Boolean).void }
  def initialize(namespace:, experiment:, editable: false)
    @namespace = namespace
    @experiment = experiment
    @editable = editable
  end

  sig { returns(T.nilable(AzureEXP::Beta::Variant)) }
  memoize def assigned_variant
    locally_assigned_variant || remotely_assigned_variant
  end

  sig { returns(T.nilable(AzureEXP::Beta::Variant)) }
  memoize def locally_assigned_variant
    experiment.variants.find { |t| t.assignment_state == AzureEXP::Beta::AssignmentState::Local }
  end

  sig { returns(T.nilable(AzureEXP::Beta::Variant)) }
  memoize def remotely_assigned_variant
    experiment.variants.find { |t| t.assignment_state == AzureEXP::Beta::AssignmentState::Remote }
  end

  sig { returns(String) }
  def value
    locally_assigned_variant&.name || "None"
  end

  sig { params(variant: AzureEXP::Beta::Variant).returns(T::Boolean) }
  def is_assigned?(variant)
    variant.name == assigned_variant&.name
  end

  def is_locally_assigned?(variant)
    variant.name == locally_assigned_variant&.name
  end
end
