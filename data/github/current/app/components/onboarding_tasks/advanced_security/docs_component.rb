# typed: true
# frozen_string_literal: true

module OnboardingTasks
  module AdvancedSecurity
    class DocsComponent < ApplicationComponent
      def initialize(show_recommended_config: true, unbundled: false)
        @show_recommended_config = show_recommended_config
        @unbundled = unbundled
      end

      def show_recommended_config?
        @show_recommended_config
      end

      def unbundled?
        @unbundled
      end
    end
  end
end
