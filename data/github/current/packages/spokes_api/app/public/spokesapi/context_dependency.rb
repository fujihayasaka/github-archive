# typed: strict
# frozen_string_literal: true

module SpokesAPI
  module ContextDependency
    sig { returns(SpokesAPI::Context) }
    def spokes_api_context
      @spokes_api_context ||= T.let(Context.new, T.nilable(SpokesAPI::Context))
    end
  end
end
