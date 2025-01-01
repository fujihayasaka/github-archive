# typed: true
# frozen_string_literal: true

module Newsies
  module Responses
    class Subscription < Newsies::Response
      def initialize(&block)
        super(Newsies::Subscription.new)
      end
    end
  end
end
