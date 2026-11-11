# frozen_string_literal: true
module ManifestAdapters
  module Composer
    module Requirements
      # Normalize requirements into the dependency graph format
      # https://getcomposer.org/doc/articles/versions.md
      # Lovingly taken and adapted from Dependabot's composer requirements parser
      # https://github.com/dependabot/dependabot-core/blob/master/composer/lib/dependabot/composer/requirement.rb

      #TODO: deal with != case
      VERSION = /(?<version>[\d\.]+([@\-]{1}[a-zA-Z]+)?)/.freeze
      OPERATOR = /(?<operator>[>=<]+)/.freeze
      OPERATOR_AND_VERSION = /#{OPERATOR.source}\s*#{VERSION.source}/.freeze
      AND_SEPARATOR = /#{OPERATOR_AND_VERSION.source}[\s,]*#{OPERATOR_AND_VERSION.source}/.freeze

      def self.parse(requirement_string)
        requirement_string = requirement_string.to_s
        return "" if requirement_string.empty?
        parsed_reqs = []
        requirement_string.split("||").each do |req|
          parsed_reqs << Parsed.new(req.strip).version
        end
        parsed_reqs.join(" || ")
      end

      class Parsed
        attr_reader :requirements

        def initialize(requirements)
          @requirements = requirements.to_s
        end

        def version
          convert_constraints(requirements)
        end

        private

        #convert constraints to format dep graph understands
        def convert_constraints(req_string)
          req_string = req_string.strip.gsub(/v(?=\d)/, "").gsub(/\.$/, "").gsub(/[a-z0-9\-_\.]*\sas\s+/i, "")

          # clean up input to provide uniform spacing between bound symbols and versions - keeps input and output more consistent
          is_operator_and_version = /\A#{OPERATOR_AND_VERSION.source}\z/.match(req_string)
          req_string = "#{is_operator_and_version[:operator]} #{is_operator_and_version[:version]}" if is_operator_and_version

          if req_string.start_with?("*", "x", "@") then ">= 0"
          elsif req_string.strip.start_with?("dev-") then "" # return blank version for branch aliases to show up blank on dep-graph (similar to latest and wildcard in NPM)
          elsif req_string.include?("*") then convert_wildcard(req_string)
          elsif req_string.include?(".x") then convert_wildcard(req_string)
          elsif req_string.match?(/^~[^>]/) then convert_tilde(req_string)
          elsif req_string.start_with?("^") then convert_caret(req_string)
          elsif req_string.match?(/\s-\s/) then convert_hyphen(req_string)
          elsif req_string.match?(/\A#{VERSION.source}\z/) then convert_exact(req_string)
          elsif req_string.match?(AND_SEPARATOR) then format_and(req_string)
          elsif is_operator_and_version then req_string
          else
            invalid_req(req_string)
          end
        end

        def invalid_req(req_string)
          # Log invalid requirement
          DependencyGraph.logger.info("invalid requirement",
            "gh.dependency_graph.package_manager" => "composer",
            "gh.dependency_graph.manifest_adapter.requirements" => req_string,
          )
          ""
        end

        def convert_exact(req_string)
          "= #{req_string}"
        end

        def convert_wildcard(req_string)
          return "" if req_string.start_with?(">", "<")

          version = req_string.gsub(/^~/, "").gsub(/(?:\.|^)[\*x]/, "")

          "~> #{version}.0"
        end

        def convert_tilde(req_string)
          version = req_string.gsub(/^~/, "")

          "~> #{version}"
        end

        def convert_caret(req_string)
          version = req_string.gsub(/^\^/, "")
          parts = version.split(".")
          first_non_zero = parts.find { |d| d != "0" }
          first_non_zero_index =
            first_non_zero ? parts.index(first_non_zero) : parts.count - 1
          upper_bound = parts.map.with_index do |part, i|
            if i < first_non_zero_index then part
            elsif i == first_non_zero_index then (part.to_i + 1).to_s
            else
              0
            end
          end.join(".")

          ">= #{version}, < #{upper_bound}"
        end

        def convert_hyphen(req_string)
          req_string = req_string
          lower_bound, upper_bound = req_string.split(/\s+-\s+/)
          if upper_bound.split(".").count < 3
            upper_bound_parts = upper_bound.split(".")
            upper_bound_parts[-1] = (upper_bound_parts[-1].to_i + 1).to_s
            upper_bound = upper_bound_parts.join(".")

            ">= #{lower_bound}, < #{upper_bound}"
          else
            ">= #{lower_bound}, <= #{upper_bound}"
          end
        end

        def format_and(req_string)
          match = req_string.match(AND_SEPARATOR)
          first_req = match.captures[0..1].join(" ")
          second_req = match.captures[2..3].join(" ")
          "#{first_req}, #{second_req}" # again, this is to have clean and uniform spacing in the output
        end
      end
    end
  end
end
