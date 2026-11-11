# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class PackageDependenciesQuery < ::Search::Query
      def self.field_list
        [:ecosystem, :is, :license, :name, :org, :severity, :sort, :version].freeze
      end

      def self.unique_field_list
        [:ecosystem, :is, :name, :severity, :sort, :version].freeze
      end
    end
  end
end
