# typed: strict
# frozen_string_literal: true

module InternalGraphqlTracingHelper
  extend T::Helpers
  extend T::Sig
  requires_ancestor { ApplicationController }

  sig { returns(T::Boolean) }
  def tracing_enabled?
    logged_in? && current_user.employee? && params && params[:_tracing] == "true"
  end

  sig { returns(T::Boolean) }
  def tracing_flamegraph_enabled?
    tracing_enabled? && params[:tracing_flamegraph] == "true"
  end
end
