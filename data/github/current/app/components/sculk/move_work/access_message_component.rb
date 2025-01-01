# typed: strict
# frozen_string_literal: true

module Sculk
  module MoveWork
    class AccessMessageComponent < ApplicationComponent

      sig { params(move_work: ::MoveWork).void }
      def initialize(move_work:)
        @move_work = move_work
      end

      sig { returns T::Boolean }
      def render?
        feature.present?
      end

      private

      sig { returns(Symbol) }
      def icon
        feature&.metadata[:icon]
      end

      sig { returns(T.nilable(::MoveWork::Feature)) }
      def feature
        move_work.feature
      end

      sig { returns(::MoveWork) }
      attr_reader :move_work
    end
  end
end
