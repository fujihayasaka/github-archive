# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class SubpageLinkFormComponent < ApplicationComponent
      sig { params(title: (String), description: (String), path: (String), icon: T.nilable(String), can_write: T::Boolean, can_read: T.nilable(T::Boolean)).void }
      def initialize(title:, description:, path:, icon: nil, can_write: true, can_read: nil)
        @title = title
        @description = description
        @path = path
        @icon = icon
        @can_write = can_write
        @can_read = T.let(can_read.nil? ? can_write : can_read, T::Boolean)
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
