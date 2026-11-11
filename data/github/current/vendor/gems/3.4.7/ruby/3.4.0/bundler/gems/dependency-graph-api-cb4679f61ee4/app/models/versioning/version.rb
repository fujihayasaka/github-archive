module Versioning
  class Version
    include Comparable

    def primary_identifier
      raise NotImplementedError
    end

    def ==(other)
      raise NotImplementedError
    end

    def <=>(other)
      return 1 unless other.parseable?

      # Infinity is always the greatest, regardless of version type.
      # Also makes sure that a named version is always contained in version range w/ an unbounded upper bound.

      return 1 if primary_identifier == Float::INFINITY
      return -1 if other.primary_identifier == Float::INFINITY


      # NamedVersions are always bigger than SemanticVersions (Infinity is the exception)
      if (primary_identifier <=> other.primary_identifier).nil?
        return 1 if self.is_a?(NamedVersion)
        return -1 if self.is_a?(SemanticVersion)
      end

      # If all else fails, this version is sorted lower than others
      return -1

    end

    def encoded
      raise NotImplementedError
    end

    def to_s
      raise NotImplementedError
    end

    def inspect
      to_s
    end

    def hash
      to_s.hash
    end

    def parseable?
      true
    end
  end
end
