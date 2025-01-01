# typed: true
# frozen_string_literal: true

class Checks::CreateGateRequest
  include GitHub::Tracing

  attr_reader :check_run, :update_properties

  trace_method(
    :call,
    span_attribute_extractor: -> (instance, *_args, **_kwargs) do
      {
        "gh.repo.id" => instance.check_run.repository_id,
        "gh.check_run.id" => instance.check_run.id,
      }
    end
  )

  def self.call(check_run:, update_properties:)
    new(
      check_run: check_run,
      update_properties: update_properties
    ).call
  end

  def initialize(check_run:, update_properties:)
    @check_run = check_run
    @update_properties = update_properties
  end

  def call
    # When a gate is deleted we auto-reject all gate requests. When this happens Actions Service will
    # send a post back to update the gate request. The gate is deleted, but the gate request is not, so we
    # want to use the gate_id instead of an instance of the gate to find the gate request
    GateRequest.create_or_update_gate_request(
      update_properties[:gate_id],
      check_run,
      update_properties[:token],
      update_properties[:gate_state],
      update_properties[:concluded],
      update_properties[:expires_at]
    )
  end
end
