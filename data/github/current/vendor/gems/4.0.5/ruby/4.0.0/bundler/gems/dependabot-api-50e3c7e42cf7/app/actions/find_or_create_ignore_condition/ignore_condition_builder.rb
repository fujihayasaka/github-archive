# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/config/ignore_condition"
require "github_helpers"

class FindOrCreateIgnoreCondition
  class IgnoreConditionBuilder
    def initialize(dep:, version:, precision_to_ignore: nil)
      @dep = dep
      @version = version
      @precision_to_ignore = precision_to_ignore
    end

    def run
      build_requirement_to_ignore(@dep)
    end

    private

    attr_reader :precision_to_ignore, :version

    def build_requirement_to_ignore(dep)
      parts = dep.version.split(".")
      precision_to_ignore ||= @precision_to_ignore || update_type(dep)

      version_parts = parts.fill(0, parts.length...[3, precision_to_ignore].max).
                      first(precision_to_ignore)
      lower_bound = [*version_parts.first(precision_to_ignore - 1), version.lowest_prerelease_suffix].
                    join(".")
      upper_bound =
        if Gem::Version.correct?(dep.version)
          [
            *version_parts.first(precision_to_ignore - 2),
            version_parts[precision_to_ignore - 2].to_i + 1,
          ].join(".")
        else
          [
            *version_parts.first(precision_to_ignore - 1),
            version_parts[precision_to_ignore - 1].to_i + 999999,
          ].join(".")
        end

      [">= #{lower_bound}", "< #{upper_bound}"]
    end

    def update_type(dep)
      prev_parts = dep.previous_version.sub("v", "").split(".")
      next_parts = dep.version.sub("v", "").split(".")

      if prev_parts[0] != next_parts[0]
        2 # major
      elsif prev_parts.length < 2 || next_parts.length < 2 || prev_parts[1] != next_parts[1]
        3 # minor
      else
        4 # patch
      end
    end
  end
end
