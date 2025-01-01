# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class SubpageLinkFormComponent < ApplicationComponent
      sig { params(title: (String), description: (String), path: (String)).void }
      def initialize(title:, description:, path:)
        @title = title
        @description = description
        @path = path
      end

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      private

      sig { returns(String) }
      def id
        @title.parameterize
      end
    end
  end
end
