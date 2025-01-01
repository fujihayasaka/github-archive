# typed: true
# frozen_string_literal: true

module Elastomer

  # The Slicer class is responsible for parsing and assembling index names such
  # that we have a coherent naming and versioning strategy for our indices.
  # Subclasses of the slicer implement various slicing strategies such as
  # date-based slicing and range-based slicing.
  class Slicer
    attr_reader :index          # name of the index
    attr_reader :index_version  # version of the index
    attr_reader :slice          # name of the slice
    attr_reader :slice_version  # version of the slice
    attr_reader :postfix        # index name post fix for distinguishing environments

    def initialize(
      fullname:      nil,
      index:         nil,
      index_version: nil,
      slice:         nil,
      slice_version: nil,
      postfix:       ::Elastomer::Environment.postfix
    )
      self.postfix = postfix
      self.index = index
      self.index_version = index_version
      self.slice = slice
      self.slice_version = slice_version
      self.fullname = fullname unless fullname.nil?
    end

    # Set the postfix string to append to index names. This postfix is most
    # useful for distinguishing between a production environment and a test
    # environment. This allows the same search cluster to be used for both
    # environments without overlapping; this is used for testing and local
    # development.
    #
    # Raises an ArgumentError if the postfix name is not valid.
    def postfix=(str)
      if str.nil?
        @postfix = nil
      elsif str.is_a?(String)
        @postfix = str.gsub(/\A-+|-+\Z/, "")  # remove leading and trailing dashes "-"
      else
        raise ArgumentError, "unrecognized postfix string: #{str.inspect}"
      end
    end

    # Returns the full index name including version and slice information.
    def fullname
      return @fullname unless @fullname.nil?
      return nil if index.nil?
      [index, index_version, slice, slice_version].compact.join("-")
    end

    # Set the full index name including version and slice information. The full
    # name will be parsed and the individual `index`, `index_version`, `slice`,
    # and `slice_version` attributes will also be set. If the full name does not
    # contain one of those terms then it will be set to `nil`.
    #
    # Raises an ArgumentError if the full index name is not valid.
    def fullname=(str)
      return if str.nil?

      index, index_version, slice, slice_version = validate_fullname(str)
      self.index = index
      self.index_version = index_version
      self.slice = slice
      self.slice_version = slice_version
    end

    # Assign the index name. This must be an String value that contains only
    # word characters in the set [a-zA-Z0-9_] and starts with alpha character.
    # Setting the index name to `nil` will clear the attribute.
    #
    # Raises an ArgumentError if the index name is not valid.
    def index=(obj)
      if obj.nil?
        @index = nil

      elsif obj.is_a?(Class) && obj <= ::Elastomer::Index
        @index = obj.name&.demodulize.underscore.tr("_", "-")
        @index = "#{@index}#{postfix_match}" if postfix

      elsif obj.is_a?(String) && obj =~ /\A#{index_match}\z/i
        @index =
          if postfix && obj !~ /#{postfix_match}\Z/
            "#{obj}#{postfix_match}"
          else
            obj
          end
      else
        raise ArgumentError, "unrecognized index name: #{obj.inspect}"
      end
    end

    # Assign the index version. This must be an Integer value or a String that
    # contains an Integer value. Setting the index version to `nil` will clear
    # the attribute.
    #
    # Raises an ArgumentError if the index version is not valid.
    def index_version=(str)
      if str.nil?
        @index_version = nil
      elsif str.is_a?(String) && str =~ /\A#{version_match}\z/
        @index_version = str
      elsif str.is_a?(Integer)
        @index_version = str.to_s
      else
        raise ArgumentError, "unrecognized index version: #{str.inspect}"
      end
    end

    # Assign the slice name. This must be an String value that contains only
    # word characters in the set [a-zA-Z0-9_]. Setting the slice name to `nil`
    # will clear the attribute.
    #
    # Raises an ArgumentError if the slice name is not valid.
    def slice=(str)
      if str.nil?
        @slice = nil
      elsif str.is_a?(String) && str =~ /\A#{slice_match}\z/
        @slice = str
      else
        raise ArgumentError, "unrecognized slice name: #{str.inspect}"
      end
    end

    # Assign the slice version. This must be an Integer value or a String that
    # contains an Integer value. Setting the slice version to `nil` will clear
    # the attribute.
    #
    # Raises an ArgumentError if the slice version is not valid.
    def slice_version=(str)
      if str.nil?
        @slice_version = nil
      elsif str.is_a?(String) && str =~ /\A#{version_match}\z/
        @slice_version = str
      elsif str.is_a?(Integer)
        @slice_version = str.to_s
      else
        raise ArgumentError, "unrecognized slice version: #{str.inspect}"
      end
    end

    # Returns the "slice alias" which is used to make the current slice the
    # primary index for handling queries to that slice. If this slicer does not
    # contain any slice information, then this method will return `nil`.
    def slice_alias
      return nil if index.nil? || slice.nil?
      [index, slice].compact.join("-")
    end

    # Returns the "index alias" which is used to make the current index the
    # primary index for handling queries. If this slicer does not contain any
    # index infrmation, then this method will return `nil`.
    def index_alias
      return nil if index.nil?
      index
    end

    # Returns the class name (as a String) for the index identified by the index
    # name.
    def index_class_name
      return nil if index.nil?

      name = index
      name = name.sub(/#{postfix_match}\z/, "") unless postfix.nil?
      name.tr("-", "_").camelize.split("::").last
    end

    # Returns `true` if the given index `name` conforms to the naming rules
    # implemented by this Slicer. Returns `false` otherwise.
    def valid_index_name?(name)
      validate_fullname(name)
      true
    rescue ArgumentError
      false
    end

    # Constructs a slice name based on the given value. Subclasses can override
    # this method to implement their own slicing strategies.
    def slice_from_value(value)
      return if value.nil?
      value.to_s
    end

    # Provides an enumerator over a range of slice names. We start with the
    # `first` and end at the `last` in the range. This method is very useful
    # when creating a completely new index and all slices need to be created.
    #
    # first - beginning of the slice range
    # last  - end of the slice range
    #
    # Example
    #
    #   enum = slice_range(1, 10)
    #   enum.to_a  #=> ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
    #
    #   slice_range(1, 10) { |slice| ... }
    #
    # Returns an Enumerator if a block is not given.
    # Raises an ArgumentError if the `first` or `last` cannot be part of a Range.
    # Raises a TypeError if the Range type cannot be iterated.
    def slice_range(first, last)
      enum = Enumerator.new do |y|
        (first..last).each do |val|
          y << slice_from_value(val)
        end
      end

      if block_given?
        enum.each { |slice| yield slice }
        self
      else
        enum
      end
    end

    # Internal: This method parses the given full index name and parses out and
    # returns the four index name parts.
    #
    # str - The full name of the index as a String
    #
    # Returns the four index name parts as an Array: [index, index_version, slice, slice_version]
    # Raises an ArgumentError if the input string could not be parsed.
    def validate_fullname(str)
      rgxp = %r/\A
                (?<index>#{index_match})                       # index name
                #{postfix_match}                               # `postfix` used for testing
                (?:-(?<index_version>#{version_match})         # optional index version number
                (?:-(?<slice>#{slice_match})                   # optional slice name
                (?:-(?<slice_version>#{version_match}))?)?)?   # optional slice version number
              \Z/ix                                            # case insensitive, extended regexn

      match = rgxp.match(str)
      raise ArgumentError, "unrecognized full-name: #{str.inspect}" if match.nil?

      index = postfix ? "#{match[:index]}#{postfix_match}" : match[:index]
      [index, match[:index_version], match[:slice], match[:slice_version]]
    end

    # Internal: Generates the correct postfix regular expression string.
    def postfix_match
      postfix ? "-#{postfix}" : nil
    end

    # Internal: Regular expression (as a String) for matching index names. This
    # will match alpha characters underscores and dashes. The index name can end
    # with a number provided that the number is not immediately preceded by a
    # dash.
    def index_match
      "[a-zA-Z_-]+?(?:(?<!-)\\d+)?"
    end

    # Internal: Regular expression (as a String) for matching slice names.
    def slice_match
      "[\\w-]+?"
    end

    # Internal: Regular expression (as a String) for matching versions. This is
    # used for both slice versions and index versions.
    def version_match
      "\\d+"
    end
  end
end
