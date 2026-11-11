# typed: true
# frozen_string_literal: true

class Codespaces::AdvancedOptions::SKUSelectListComponent < ApplicationComponent
  attr_reader :availability_contexts, :warning_message, :show_prebuild_availability, :location, :vscs_target, :repository, :ref_name, :devcontainer_path

  def initialize(availability_contexts:, show_prebuild_availability:, location:, vscs_target:, ref_name:, repository:, devcontainer_path:)
    @availability_contexts = availability_contexts
    @show_prebuild_availability = show_prebuild_availability
    @location = location
    @vscs_target = vscs_target
    @ref_name = ref_name
    @repository = repository
    @devcontainer_path = devcontainer_path

    # Note that this only set up to handle warnings for new codespaces and not SKU transitions.
    if availability_contexts.any? && selectable_skus.none?
      @warning_message = Codespaces::Skus::NO_VALID_MACHINE_TYPES_CATCHALL_MESSAGE
    end
  end

  def is_default_sku?(sku)
    sku == default_sku
  end

  memoize def default_sku
    (availability_contexts.detect(&:default)&.sku || selectable_skus.first)
  end

  memoize def selectable_skus
    availability_contexts.filter_map { |r| r.sku if r.enabled }
  end

end
