# typed: strict
# frozen_string_literal: true

module App
  # Sinatra::Base doesn't just mutate `params` for each request, it _replaces_ the ivar. This means that
  # any references saved early in the request don't accurately reflect the current state of the request.
  # For this reason we need to reference a controller interface whose implementation is guaranteed to be up to date.
  module IController
    extend T::Sig
    extend T::Helpers

    interface!

    sig { abstract.returns(T.untyped) }
    def params; end

    sig { abstract.returns(T.untyped) }
    def env; end

    sig { abstract.returns(T.nilable(Users::IUser)) }
    def current_user; end
  end
end
