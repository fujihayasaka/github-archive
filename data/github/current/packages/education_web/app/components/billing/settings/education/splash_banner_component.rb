# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      class SplashBannerComponent < ApplicationComponent
        sig { void }
        def initialize
        end

        sig { returns(T::Boolean) }
        def render?
          true
        end
      end
    end
  end
end
