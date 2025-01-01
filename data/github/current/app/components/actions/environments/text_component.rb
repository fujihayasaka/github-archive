# typed: true
# frozen_string_literal: true

module Actions
  module Environments
    class TextComponent < ApplicationComponent

      def initialize(environments:)
        @environments = environments.uniq
      end

      def render?
        @environments.any?
      end
    end
  end
end
