# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class RateLimitsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_accessor :user

      def initialize(user, context)
        @user = user
        @context = context
      end

      def page_title
        "#{@user} - Rate Limits"
      end

      def columns
        Api::RateLimitConfiguration::ALL_FAMILIES
      end

      def value(column)
        config = Api::RateLimitConfiguration.for(column, @context)
        throttler = Api::ConfigThrottler.new(config)
        throttler.check.remaining
      end
    end
  end
end
