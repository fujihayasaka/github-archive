# typed: true
# frozen_string_literal: true

module Notifyd

  # Build the proper hydro topic name based on the target environment and the version
  module HydroTopic
    TARGETS = {
      production: "notifyd",
      staging: "notifyd-staging",
    }

    class Topic
      attr_reader :target, :version, :format_version

      def initialize(target: :production, version:, format_version:)
        @target = TARGETS[target]
        @version = version
        @format_version = format_version
      end

      def to_s
        @to_s ||= "#{target}.#{version}.Notify"
      end
    end

    module V0
      def self.new(target: :production)
        Topic.new(target: target, version: "v0", format_version: Hydro::Topic::FormatVersion::V1)
      end
    end

    module V1
      def self.new(target: :production)
        Topic.new(target: target, version: "v1", format_version: Hydro::Topic::FormatVersion::V2)
      end
    end
  end
end
