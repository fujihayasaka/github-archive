# typed: true
# frozen_string_literal: true

module Analytics
  class OctolyticsId
    VERSION     = "GH1.1"
    INT_32_MAX  = 2**31 - 1
    UINT_32_MAX = 2**32 - 1
    UINT_64_MAX = 2**64 - 1

    attr_reader :version

    # Public: Create a new spec-compliant Octolytics ID
    #
    # Returns an Analytics::OctolyticsId
    def self.generate
      new(
        version: VERSION,
        value: rand(INT_32_MAX),
        timestamp: Time.now.to_i
      )
    end

    # Public: Coerce an OctolyticsId from a serialized string or integer
    # representation.
    #
    # coercable - A String or Integer representation of an OctolyticsId
    #
    # Returns an Analytics::OctolyticsId. Throws a CoercionError if the
    # `coercable` cannot be parsed.
    def self.coerce(coercable)
      case coercable
      when self    then coercable
      when Integer then from_i(coercable)
      when String  then from_s(coercable)
      else raise CoercionError.new(coercable)
      end
    end

    def self.from_i(int)
      raise CoercionError.new(int) if int > UINT_64_MAX

      new(
        version: VERSION,
        value: int >> 32,
        timestamp: int & UINT_32_MAX # Mask to lower 32 bits
      )
    end
    private_class_method :from_i

    def self.from_s(string)
      raise CoercionError.new(string) unless string.valid_encoding?

      match = string.match(/
        (?<version>GH\d+\.\d+)\.
        (?<value>\d{2,10})\.
        (?<timestamp>\d{2,10})
       /x)

      raise CoercionError.new(string) unless match

      new(
        version: match[:version],
        value: match[:value],
        timestamp: match[:timestamp]
      )
    end
    private_class_method :from_s

    # Public: Instantiate an new OctolyticsId.
    #
    # value     - A random Integer or numeric String representing the ID.
    # version   - A String ID format version specifier.
    # timestamp - An Integer number of seconds since the Epoch.
    #
    # Returns an Analytics::OctolyticsId.
    def initialize(value:, version:, timestamp:)
      @value     = value
      @version   = version
      @timestamp = timestamp
    end

    def ==(other)
      other.is_a?(self.class) &&
      value == other.value &&
      version == other.version &&
      timestamp == other.timestamp
    end
    alias eql? ==

    def hash
      to_s.hash
    end

    # Public: Return the serialized integer representation of the ID.
    #
    # Returns an Integer.
    def to_i
      (value << 32) + timestamp
    end

    # Public: Return the serialized string representation of the ID.
    #
    # Returns a String.
    def to_s
      [version, value, timestamp].join(".")
    end

    # Public: Return the serialized string representation of the ID without a
    # verion prefix.
    #
    # Returns a String.
    def unversioned
      [value, timestamp].join(".")
    end

    def value
      @value.to_i
    end

    def timestamp
      @timestamp.to_i
    end

    class CoercionError < ArgumentError
      def initialize(value)
        super("Can't coerce #{value.inspect} to #{OctolyticsId}")
      end

      def failbot_context
        { app: "github-octolytics" }
      end
    end
  end
end
