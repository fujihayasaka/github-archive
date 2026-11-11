# typed: true
# frozen_string_literal: true

class Stafftools::AzureExp::VariantMenuItemComponent < ApplicationComponent
  attr_reader :namespace, :experiment, :variant, :is_assigned

  sig { params(namespace: AzureEXP::Beta::Namespace, experiment: AzureEXP::Beta::Experiment, variant: T.nilable(AzureEXP::Beta::Variant), is_assigned: T::Boolean).void }
  def initialize(namespace:, experiment:, variant:, is_assigned:)
    @namespace = namespace
    @experiment = experiment
    @variant = variant
    @is_assigned = is_assigned
  end

  sig { returns(String) }
  def label
    variant&.name || "None"
  end
end
