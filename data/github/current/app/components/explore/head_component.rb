# typed: strict
# frozen_string_literal: true

module Explore
  class HeadComponent < ApplicationComponent
    extend T::Sig

    sig { returns(T::Boolean) }
    def render?
      return false if GitHub.multi_tenant_enterprise?
      true
    end
  end
end
