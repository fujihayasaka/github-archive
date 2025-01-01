# typed: true
# frozen_string_literal: true

module AzureEXP::Beta
  class OverridableExpAssignmentProvider
    include GitHub::Memoizer

    sig { params(participant: Participant, namespace: String, surface: T.nilable(String), disable_cache: T::Boolean).void }
    def initialize(participant:, namespace:, surface: nil, disable_cache: false)
      @participant = participant
      @namespace = namespace
      @surface = surface
      @provider = AzureEXP::ExpAssignmentProvider.new(participant:, namespace:, surface:, disable_cache:, override_variants: override_variants)
    end

    delegate :in_group?, :variants, :assignment_context, to: :@provider

    private

    sig { returns(T::Hash[String, AzureEXP::Beta::ParameterType]) }
    def override_variants
      return {} unless @participant.staff? || Rails.env.development?
      AzureEXP::Beta::LocalAssignmentService.parameters(participant: @participant, namespace: @namespace)
    end
  end
end
