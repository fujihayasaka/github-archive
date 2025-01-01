# typed: true
# frozen_string_literal: true

module AzureEXP
  class ExpAssignmentProvider
    extend T::Sig
    include Instrumentation::Model

    AZURE_EXP_PATH = "exp00451/a869f069-fe31-46f4-8784-c164f79eb133-githubprod/api/v1/tas"

    def initialize(participant:, namespace:, surface: nil, timeout: AzureEXP::AssignmentClient::CONNECTION_TIMEOUT,
      open_timeout: AzureEXP::AssignmentClient::CONNECTION_OPEN_TIMEOUT, disable_cache: false, custom_params: {}, override_variants: {}
    )
      @participant = T.let(participant, Beta::Participant)
      @variant_namespace = namespace
      @assignment_surface = surface || namespace
      @timeout = timeout
      @open_timeout = open_timeout
      @custom_params = custom_params
      @disable_cache = disable_cache
      @override_variants = override_variants
    end

    def variants
      return @variants if defined? @variants
      @variants = begin
        variants = assignment.variants_by_namespace(@variant_namespace)
        variants = variants.merge(@override_variants)
      end
    end

    def assignment_context
      @context ||= assignment.assignment_context
    end

    def in_group?(group_name:, expected_value: true)
      Array(expected_value).include?(variants[group_name])
    end

    def clear_exp_cache
      client.clear_cache(params)
    end

    def assignment_namespaces
      assignment.namespaces
    end

    private

    sig { returns(Beta::Participant) }
    attr_reader :participant

    attr_reader :timeout, :open_timeout

    def assignment
      return @assignment if defined?(@assignment)
      @assignment = client.get_assignment(params)
      send_hydro_event
      @assignment
    end

    def client
      @client ||= AzureEXP::AssignmentClient.new(AZURE_EXP_PATH, namespace: @variant_namespace, timeout: @timeout, open_timeout: @open_timeout, disable_cache: @disable_cache)
    end

    def send_hydro_event
      GlobalInstrumenter.instrument "exp.responded", {
        request_context: GitHub.context.to_hash,
        namespace: @variant_namespace,
        assignment_surface: @assignment_surface,
        current_experiments: variants.to_json,
        assignment_context: assignment_context,
        called: Time.current,
        randomization_unit: participant.type.to_sym,
        randomization_id: participant.randomization_id
      }
    end

    def params
      @custom_params.merge(
      {
        "clientid": participant.randomization_id,
        "surface": @assignment_surface,
        "ghstaff": participant.staff?,
      })
    end
  end
end
