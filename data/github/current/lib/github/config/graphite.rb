# typed: true
# frozen_string_literal: true

require "graphite"

module GitHub
  module Config
    module Graphite
      def graphite
        @graphite ||= ::Graphite.new(GitHub.graphite_url)
      end

      def rails_version_key
        "rails#{Rails.version.split(".")[0, 2].join("_")}"
      end
    end
  end

  extend Config::Graphite
end
