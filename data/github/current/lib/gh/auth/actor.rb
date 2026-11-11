# typed: strict
# frozen_string_literal: true

require "feature_flag/i_feature_target"

module GH
  module Auth
    module Actor
      extend T::Helpers

      interface!

      include Kernel
      include FeatureFlag::IFeatureTarget

      sig { abstract.returns(T.nilable(Integer)) }
      def id; end

      sig { abstract.returns(T.nilable(String)) }
      def display_login; end

      sig { abstract.returns(T.nilable(String)) }
      def ability_type; end
    end
  end
end
