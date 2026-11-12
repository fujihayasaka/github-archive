module Versioning
  class VersionRange
    attr_reader :lower_bound, :upper_bound

    LOWEST_BOUND = SemanticVersion.new(
      major: 0,
      minor: 0,
      patch: 0,
    )

    HIGHEST_BOUND = SemanticVersion.new(
      major: Float::INFINITY,
      minor: Float::INFINITY,
      patch: Float::INFINITY,
    )

    def initialize(lower_bound: nil, upper_bound: nil)
      @lower_bound = lower_bound.presence || LOWEST_BOUND
      @upper_bound = upper_bound.presence || HIGHEST_BOUND
    end

    def valid?
      return lower_bound == upper_bound if possible_name_range?
      lower_bound <= upper_bound
    end

    def possible_name_range?
       lower_bound.is_a?(NamedVersion) || upper_bound.is_a?(NamedVersion)
    end

    def encoded_lower_bound
      lower_bound.encoded.to_i
    end

    def encoded_upper_bound
      upper_bound.encoded.to_i
    end

    def lower_bound?
      true
    end

    def upper_bound?
      true
    end

    def upper_bound_inclusive?
      true
    end

    def lower_bound_inclusive?
      true
    end

    def to_requirements_set(allow_named_versions:)
      if possible_name_range?
        if valid?
          req_set = RequirementSet.new(ranges: [
            [Requirement.new("=", "#{@lower_bound}", allow_named_versions: allow_named_versions)]
          ], allow_named_versions: allow_named_versions)

          return req_set
        else
          return RequirementSet.new(ranges: [], allow_named_versions: allow_named_versions)
        end
      end

      # VersionRange is not used in prod, only specs. The HIGHEST_BOUND constant gets converted to "Xfinity.x.x" which is not re-parsable by the VersionParser and it returns an UnparsableVersion.
      # Instead of modifying the VersionParser/prod code, we'll just return a more real-world unbounded req set here.

      if upper_bound == HIGHEST_BOUND
        req_set = RequirementSet.new(ranges: [
          [Requirement.new(">=", "#{@lower_bound}", allow_named_versions: allow_named_versions)]
        ], allow_named_versions: allow_named_versions)

        return req_set
      end

      RequirementSet.new(ranges: [
           [Requirement.new(">=", "#{@lower_bound}", allow_named_versions: allow_named_versions), Requirement.new("<=", "#{@upper_bound}", allow_named_versions: allow_named_versions)]
         ], allow_named_versions: allow_named_versions)
    end
  end
end
