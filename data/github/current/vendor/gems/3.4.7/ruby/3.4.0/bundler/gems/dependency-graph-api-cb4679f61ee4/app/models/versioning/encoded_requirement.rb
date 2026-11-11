module Versioning
  class EncodedRequirement
    def initialize(requirement)
      @requirement = requirement
    end

    def encoded_lower_bound
      return 0 unless requirement.lower_bound?

      encoded = requirement.lower_bound.encoded.to_i
      requirement.lower_bound_inclusive? ? encoded : encoded + 1
    end

    def encoded_upper_bound
      return EncodedVersion::MAX unless requirement.upper_bound?

      encoded = requirement.upper_bound.encoded.to_i
      requirement.upper_bound_inclusive? ? encoded : encoded - 1
    end

    private

    attr_reader :requirement
  end
end
