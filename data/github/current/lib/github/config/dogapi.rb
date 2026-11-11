# typed: true
# frozen_string_literal: true

require "dogapi"

module GitHub
  module Config
    module Dogapi
      attr_reader :source
      def dogapi
        return @source if defined?(@source)
        start_dogapi
      end

      def start_dogapi
        if Rails.env.test?
          @source ||= NullDogapi.new
        else
          @source ||= ::Dogapi::Client.new(ENV["DATADOG_API_KEY"], ENV["DATADOG_APP_KEY"], silent: true, timeout: 5)
        end
      end

      class NullDogapi
        def initialize(*)
        end

        def get_points(*)
          ["200", []]
        end
      end
    end
  end

  extend Config::Dogapi
end
