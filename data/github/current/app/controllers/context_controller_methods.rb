# typed: true
# frozen_string_literal: true

module ContextControllerMethods
  extend T::Helpers
  extend T::Sig

  requires_ancestor { ApplicationController }

  abstract!

  sig { abstract.returns(T.untyped) }
  def current_context; end

  # Set the sticky context.
  def set_context
    return unless logged_in?

    if session[:context] != current_context.to_s
      session[:context] = context_path(current_context)
    end
  end
end
