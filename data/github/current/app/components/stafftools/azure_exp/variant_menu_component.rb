# typed: true
# frozen_string_literal: true

class Stafftools::AzureExp::VariantMenuComponent < ApplicationComponent
  attr_reader :namespace, :experiment, :assignment

  sig do
    params(
      namespace: AzureEXP::Beta::Namespace,
      experiment: AzureEXP::Beta::Experiment,
      assignment: T.nilable(AzureEXP::Beta::Variant),
    ).void
  end
  def initialize(namespace:, experiment:, assignment:)
    @namespace = namespace
    @experiment = experiment
    @assignment = assignment
  end

  sig { returns(String) }
  def value
    assignment&.name || "None"
  end

  sig { params(variant: T.nilable(AzureEXP::Beta::Variant)).returns(T::Hash[Symbol, T.untyped]) }
  def menu_item_arguments(variant: nil)
    variant_name = variant&.name
    {
      label: variant_name,
      href: azure_exp_local_assignments_path,
      form_arguments: {
        method: :put,
        inputs: [{ name: :namespace, value: namespace.name },
                  { name: :experiment, value: experiment.name },
                  { name: :variant, value: variant_name }]
      },
      test_selector: "variant-menu-item",
    }
  end
end
