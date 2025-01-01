# typed: strict
# frozen_string_literal: true

module Substrate
  # Sinatra::Base doesn't just mutate `params` for each request, it _replaces_ the ivar. This means that
  # any references saved early in the request don't accurately reflect the current state of the request.
  # For this reason we need to reference a controller interface whose implementation is guaranteed to be up to date.
  module IRepositoryOwner
    extend T::Helpers

    include Kernel

    interface!
  end
end
