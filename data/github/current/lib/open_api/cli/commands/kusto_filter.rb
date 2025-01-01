# typed: true
# frozen_string_literal: true

require "open_api/description/overlay"

module OpenApi
  module CLI
    module Commands
      # Generate Kusto filter for Service Tier 1
      class KustoFilter < Command

        PATH_PARAM_PATTERN = "[^/]+"

        def run
          tiers = {}
          OpenApi.root.glob("operations/**/*.yaml").each do |file|
            content = YAML.load_file(file)
            if (tier = content.dig("x-github-internal", "service-tier")) && (path = content.dig("x-github-internal", "path"))
              parts = path.split("/").map do |part|
                case part
                when /\A\{/
                  PATH_PARAM_PATTERN
                else
                  part
                end
              end
              tiers[tier] ||= Set.new
              tiers[tier] << parts
            end
          end
          clauses = UnambiguousPrefixer.prefixes(tiers[1], tiers[2]).map do |parts|
            pattern = parts.join("/")
            if tiers[1].include?(parts) && !parts.include?(PATH_PARAM_PATTERN)
              [0, %Q(path == "#{pattern}").dup]
            else
              if parts.include?(PATH_PARAM_PATTERN)
                [2, %Q(path matches regex "^#{pattern}").dup]
              else
                [1, %Q(path startswith "#{pattern}").dup]
              end
            end
          end.sort.map(&:last)
          # Ensure /graphql is included, even though it's not defined using OpenAPI
          clauses.unshift(%q(| where path == "/graphql"))
          # Add 'or' booleans and indentation to each clause
          clauses[1..-1].each do |clause|
            clause.insert(0, "     or ")
          end
          puts clauses
        end

        # Condenses a list of path components to a list of common prefixes, avoiding any prefixes
        # that would match a second list.
        class UnambiguousPrefixer
          def self.prefixes(includes, excludes)
            new(includes, excludes).result
          end

          def initialize(includes, excludes)
            @tree = {}
            mark_tree!(includes, true)
            mark_tree!(excludes, false)
          end

          def mark_tree!(paths, leaf_value)
            paths.each do |path|
              path.each_with_index.reduce(@tree) do |memo, (component, index)|
                if index == path.size - 1
                  memo[component] = leaf_value
                elsif !memo[component].is_a?(Hash)
                  memo[component] = {}
                end
                memo[component]
              end
            end
          end

          def result
            return @result if defined?(@result)
            @result = []
            collect_result!(@tree, [])
            @result
          end

          private

          def collect_result!(node, walk)
            if !walk.empty? && prefix?(node)
              @result << walk
            else
              node.each do |key, value|
                case value
                when true
                  @result << (walk + [key])
                when Hash
                  collect_result!(value, walk + [key])
                end
              end
            end
          end

          def prefix?(node)
            if node == true
              true
            elsif node.is_a?(Hash)
              node.values.all?(&method(:prefix?))
            else
              false
            end
          end
        end
      end
    end
  end
end
