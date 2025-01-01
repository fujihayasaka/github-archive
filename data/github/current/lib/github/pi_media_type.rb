# typed: true
# frozen_string_literal: true

require "set"

# NOTE: This file is copied from the private repo github/pi,
# allowing us to stop requiring the gem, since the name conflicts
# with a public gem on Rubygems.

# Represents a parsed media type.
module GitHub
  class PiMediaType
    # Initializes a media type.
    #
    # type - String type from a header:
    #        "application/vnd.foo+json; charset=utf-8"
    def initialize(type = nil)
      @string = type.to_s
      @version = @main_type = @sub_type = @suffix = @options = @vendor = @api_options = nil
    end

    # Public: Gets the type of a media type.  This is the first segment in
    # the above type: "application"
    #
    # Returns a String.
    def main_type
      @main_type || parse_and_return(:@main_type)
    end

    # Public: Gets the sub type of a media type.  This is the last segment in
    # the above type: "vnd.foo"
    #
    # Returns a String.
    def sub_type
      @sub_type || parse_and_return(:@sub_type)
    end

    # Public: Gets the optional suffix of a media type.  This is the segment
    # after the `+` in the above type: "json".
    #
    # Returns a String.
    def suffix
      @suffix || parse_and_return(:@suffix)
    end

    # Public: Gets the optional vendor name of a media type.  This is taken
    # from sub types with a `vnd.` prefix: "foo".
    #
    # Returns a String.
    def vendor
      @vendor || parse_and_return(:@vendor)
    end

    # Public: Gets whether the media type is vendor-specific.
    #
    # Returns true or false.
    def vendor?
      !vendor.empty?
    end

    # Public: Gets the version of the media type. Opts for the sub_type version first otherwise
    # returns version specified in the parameters
    #
    # Returns a String
    def version
      @version || parse_and_return(:@version) || params["version"]
    end

    # Public: Gets the custom options for a media type.  These are key/value
    # pairs specified after the main type: "charset=utf-8"
    #
    # Returns a Hash.
    def params
      @params || parse_and_return(:@params)
    end

    def empty?
      @string.empty?
    end

    # Public: Gets the original media type representation.
    #
    # Returns a String.
    def to_s
      @string
    end

    def inspect
      %(#<%s %s>) % [self.class, @string.inspect]
    end

    # Parses the given type into the various properties.  Called lazily on
    # a media type the first time a property is accessed.
    #
    # ivar - A symbol instance variable to return to the accessor calling this.
    #
    # Returns an Object (depending on the ivar).
    def parse_and_return(ivar)
      @params = {}
      @suffix = ""
      @vendor = ""

      pieces = @string.split ";"

      # separate the type from the key/value options
      @main_type, @sub_type = pieces.empty? ? ["", ""] : pieces.shift.strip.split("/")
      @sub_type ||= ""

      @sub_type = @sub_type.sub(/\+(.+)\z/) do |_s|
        @suffix = $1; nil
      end

      if @sub_type =~ /vnd\.([^\.]+)(?:\.(.*))?/
        @vendor  = $1
        @version = $2
      end

      # parse the key/value options
      pieces.each do |pair|
        key, value = pair.strip.split("=")
        @params[key] = value
      end

      instance_variable_get ivar
    end
  end
end
