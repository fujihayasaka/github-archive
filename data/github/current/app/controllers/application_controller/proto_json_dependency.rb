# typed: strict
# frozen_string_literal: true

module ApplicationController::ProtoJsonDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  # Helper to render a proto as JSON. It adds the "X-Proto-JSON" header to the response so the client knows
  # that the response is in proto JSON format. This is helpful for migrations where the proto JSON doesn't
  # exaclty match the old JSON format.
  # NOTE: we type `proto` as `T.untyped` because the Sorbet shim
  # `Google::Protobuf::AbstractMessage` (the common parent that tapioca-generated
  # protobuf RBIs subclass) does not exist as a constant at runtime, so we can't
  # reference it from a `sig` here. Callers are expected to pass a generated
  # proto message that responds to `#to_json`.
  sig do
    params(
      proto:  T.untyped, # Proto message to render as JSON in the response body.
      status: T.nilable(T.any(Symbol, Integer)), # The HTTP status code to return. Defaults to 200.
    ).returns(T.untyped)
  end
  def render_proto_json(proto:, status: :ok)
    response.headers["X-Proto-JSON"] = "true"

    render json: proto, status: status
  end
end
