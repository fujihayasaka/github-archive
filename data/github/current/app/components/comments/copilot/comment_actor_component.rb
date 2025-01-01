# typed: true
# frozen_string_literal: true

module Comments
  module Copilot
    class CommentActorComponent < ApplicationComponent
      attr_reader :actor

      def initialize(actor:)
        @actor = actor
      end
    end
  end
end
