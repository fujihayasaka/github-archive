# typed: strict
# frozen_string_literal: true

module App
  module IExecContextAccessor
    extend T::Sig
    extend T::Helpers

    interface!

    sig { abstract.returns(App::IContext) }
    def exec_context; end
  end
end
