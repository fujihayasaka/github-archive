module Versioning
  class EncodedVersion
    MAX = (2 ** 48) - 1
    MAX_PER_COMPONENT = (2 ** 16) - 1

    def initialize(version)
      @version = version
    end

    def encoded
      self
    end

    def to_i
      encoded_major + encoded_minor + encoded_patch
    end

    private

    attr_reader :version

    def encoded_major
      constrain(major) << 32
    end

    def encoded_minor
      constrain(minor) << 16
    end

    def encoded_patch
      constrain(patch)
    end

    def constrain(value)
      [value, MAX_PER_COMPONENT].min
    end

    def major
      version.major
    end

    def minor
      version.minor
    end

    def patch
      version.patch
    end
  end

  class NoEncodedVersionError < StandardError; end

  class InvalidEncodedVersion < EncodedVersion
    def to_i
      raise NoEncodedVersionError
    end
  end
end
