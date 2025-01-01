# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module ContentExclusion
      extend T::Helpers
      extend T::Sig

      include GitHub::Memoizer
      include Copilot::Businesses::Signatures

      abstract!

      sig { returns(T::Boolean) }
      def content_exclusion_available?
        copilot_standalone? || business_object.feature_enabled?(:content_exclusions_ga)
      end
    end
  end
end
