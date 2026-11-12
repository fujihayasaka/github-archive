# typed: strict
# frozen_string_literal: true

module OctoCore
  module Env
    extend T::Sig

    autoload :Base, "octo_core/env/base"
    autoload :Coordinator, "octo_core/env/coordinator"
  end
end
