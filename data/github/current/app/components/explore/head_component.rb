# typed: strict
# frozen_string_literal: true

module Explore
  class HeadComponent < ApplicationComponent
    sig { returns(T::Boolean) }
    def render?
      return false if GitHub.multi_tenant_enterprise?
      true
    end
  end
end
