require_relative "./version_parser"

module Versioning
  class Requirement
    JOIN_WITH  = " "
    SPLIT_WITH = /([=><^~]+)\s*([^\s,]+)(.+)?/
    WILDCARD   = ""

    attr_reader :operator, :requirement, :allow_named_versions

    delegate :encoded_lower_bound, :encoded_upper_bound, to: :encoded

    def self.deserialize(string, allow_named_versions:)
      return wildcard if string.blank?

      match, operator, requirement, rest = Array(string.match(SPLIT_WITH))
      return invalid(string) if !match || rest.present? || (allow_named_versions && invalid_name_requirement?(operator, requirement, allow_named_versions))

      new(operator, requirement, allow_named_versions: allow_named_versions)
    end

    def self.wildcard
      new(nil, nil, allow_named_versions: false)
    end

    def self.invalid(string)
      new(nil, string, allow_named_versions: false)
    end

    def self.invalid_name_requirement?(operator, requirement, allow_named_versions)
      Versioning::GenericVersionParser.valid_named_version?(allow_named_versions, requirement) && operator != "="
    end

    def initialize(operator = nil, requirement = nil, allow_named_versions:)
      @requirement = requirement
      @operator    = Operator.parse(operator)
      @allow_named_versions = allow_named_versions
    end

    def encoded
      @encoded ||= EncodedRequirement.new(self)
    end

    def lower_bound?
      # For practical purposes, a lower bound of 0.0.0 is the same as no lower bound.
      operator.lower_bound? && lower_bound != version_zero
    end

    def lower_bound_inclusive?
      operator.inclusive?
    end

    def requirement_version
      @requirement_version ||= ::Versioning::VersionParser.parse(requirement, allow_named_versions: allow_named_versions)
    end

    def is_version_semantic?
      requirement_version.is_a? SemanticVersion
    end

    def lower_bound
      GenericVersionParser.generate(
        allow_named_versions: allow_named_versions,
        primary_identifier: operator.lower_bound? ? primary_identifier : 0,
        minor: minor == infinity ? 0 : minor,
        patch: patch == infinity ? 0 : patch,
        additional_fields: additional_fields,
        prerelease: prerelease,
      )
    end

    def upper_bound?
      operator.upper_bound?
    end

    def upper_bound_inclusive?
      operator.inclusive?
    end

    def upper_bound
      GenericVersionParser.generate(
        allow_named_versions: allow_named_versions,
        primary_identifier: primary_identifier,
        minor:      minor_upper_bound,
        patch:      patch_upper_bound,
        additional_fields: additional_fields_upper_bound,
        prerelease: prerelease_upper_bound,
      )
    end

    def ==(other)
      return unless other.is_a?(Requirement)

      operator == other.operator && requirement == other.requirement
    end

    def cover?(version)
      # cover? *specifically* doesn't care about inclusivity in submitted versions because
      # it is *only* used for exact semver comparisons (argument shouldn't represent a range).
      return false if lower_bound? && is_upper_bound_below_my_lower_bound?(version, true)
      return false if upper_bound? && is_lower_bound_above_my_upper_bound?(version, true)

      true
    end

    # Public: Do the bounds of the other requirement overlap with the bounds
    # of this requirement?
    #
    # Returns a Boolean.
    def overlap?(other)
      # Requirements can have a lower, and upper, or both. They also have optional inclusivity.
      #  For a requirement, an exact version ( = 1.2.3 ) is inclusive on upper and lower bounds, both of which are 1.2.3.
      if lower_bound?
        return false if other.upper_bound? && is_upper_bound_below_my_lower_bound?(other.upper_bound, other.upper_bound_inclusive?)
      end

      if upper_bound?
        return false if other.lower_bound? && is_lower_bound_above_my_upper_bound?(other.lower_bound, other.lower_bound_inclusive?)
      end

      true
    end

    # Public: Does every possible version of the other requirement fall within the
    # bounds of this requirement?
    #
    # Returns a Boolean.
    def contain?(other)
      if lower_bound?
        # Left: > 1.2.3 , Right: < 1.3
        # if we have a lower bound and the other does not, then we do not contain other
        return false unless other.lower_bound?

        # if the other lower bound is below ours, we do not contain other
        return false if is_lower_bound_below_my_lower_bound?(other.lower_bound, other.lower_bound_inclusive?)
      end

      if upper_bound?
        # Left: < 1.2.3 , Right: > 1.2
        # If we are upper bounded but the other is not, we know we don't contain the max version that could satisfy the other.
        return false unless other.upper_bound?

        # if the other upper bound is above ours, we do not contain other
        return is_upper_bound_contained_by_my_upper_bound?(other.upper_bound, other.upper_bound_inclusive?)
      end
      
      # if we have no lower bound and no upper bound, we are infinite
      # and we must contain other
      true
    end

    def valid?
      (requirement.present? && operator.present?) || wildcard?
    end

    def wildcard?
      requirement.blank? && operator.blank?
    end

    def serialize
      return WILDCARD if wildcard?


      [operator, requirement].join(JOIN_WITH).strip
    end

    private

    # Trying to make the below methods *really* hard to misunderstand.
    # o : exclusive boundary
    # . : inclusive boundary
    # - : range
    # So, if you had a req string of: "> 1.2.3, <= 3.4.5" you could think of it like:
    #   o-----------------.
    #   1.2.3 < X <= 3.4.5
    # It's useful for illustrating overlap scenarios, like between these two req strings:
    #  "> 1.0.0, <= 1.5.0":     o----------.
    #  ">= 1.2.3, < 1.5.0":          .-----o
    # The dashes aren't significant, just used to visualize range and overlap.

    def is_upper_bound_below_my_lower_bound?(version, version_is_inclusive)
      # self:       o----         o----      .----       .----
      # other:  ----o         ----.      ----o       ----.
      # The same boundary value *only* implies overlap if both versions are inclusive.
      # The first three examples above are "below_my_lower_bound?" but the last is not.
      if lower_bound_inclusive? && version_is_inclusive
        version < lower_bound
      else
        version <= lower_bound
      end
    end

    def is_upper_bound_contained_by_my_upper_bound?(version, version_is_inclusive)
      # self:  ----o      ----.      ----o       ----.
      # other: ----o      ----o      ----.       ----.
      # For containment, overlap implies containment when:
      #  self is inclusive (all <= imply containment then)
      #  self and other are both exclusive
      # The first, second, and fourth example imply containment, but the third does not.
      if upper_bound_inclusive? || (!upper_bound_inclusive? && !version_is_inclusive)
        version <= upper_bound
      else
        version < upper_bound
      end
    end

    def is_lower_bound_below_my_lower_bound?(version, version_is_inclusive)
      # self:    o----     .----     .----     .-----   o----
      # other:  .-----    o-----     o----     .-----   o----
      #
      # The first three examples above are "below_my_lower_bound?" but the latter two are not.
      if !lower_bound_inclusive? && version_is_inclusive
        # this case corresponds to the second and third diagrams above, where the left
        # side is exclusive and the right side is inclusive.
        version <= lower_bound
      else
        version < lower_bound
      end
    end

    def is_lower_bound_above_my_upper_bound?(version, version_is_inclusive)
      # self:  ----o         ----.      ----o       ----.
      # other:     o----         o----      .----       .----
      # The same boundary value *only* implies overlap if both versions are inclusive.
      # The first three examples above are "above_my_upper_bound?" but the last is not.
      if upper_bound_inclusive? && version_is_inclusive
        version > upper_bound
      else
        version >= upper_bound
      end
    end

    def minor_upper_bound
      vary_minor? ? infinity : minor
    end

    def patch_upper_bound
      vary_patch? ? infinity : patch
    end

    def additional_fields_upper_bound
      vary_additional_fields? ? additional_fields[0..-2] << infinity : additional_fields
    end

    def prerelease_upper_bound
      prerelease unless vary_patch?
    end

    def primary_identifier
      requirement_version.primary_identifier
    end

    def minor
      requirement_version.minor if is_version_semantic?
    end

    def patch
      requirement_version.patch if is_version_semantic?
    end

    def additional_fields
      requirement_version.additional_fields if is_version_semantic?
    end

    def prerelease
      requirement_version.prerelease if is_version_semantic?
    end

    def most_specified
      requirement_version.most_specified if is_version_semantic?
    end

    def infinity
      Float::INFINITY
    end

    def vary_minor?
      operator.vary?(:minor, most_specified) &&
        !zeroth_release?
    end

    def vary_patch?
      operator.vary?(:patch, most_specified)
    end

    def vary_additional_fields?
      operator.vary?(:additional_fields, most_specified)
    end

    def zeroth_release?
      primary_identifier == 0
    end

    def version_zero
      GenericVersionParser.generate(
        allow_named_versions: allow_named_versions,
        primary_identifier: 0,
        minor: 0,
        patch: 0,
        additional_fields: additional_fields,
        prerelease: prerelease,
      )
    end
  end
end
