# typed: strict
# frozen_string_literal: true

module SpokesAPI
  module Util
    include Kernel

    extend self

    OID_REGEXP = /\A[a-f0-9]{40}\z/

    # Check if a given string is a valid 40 char OID
    #
    # oid - String to check
    #
    # Returns true when oid is a valid oid
    sig { params(oid: T.nilable(String)).returns(T::Boolean) }
    def valid_oid?(oid)
      oid.is_a?(String) && oid.bytesize == 40 && OID_REGEXP.match?(oid.b)
    end

    # Convert an object type enum to its corresponding string name.
    #
    # obj_type - Symbol object type enum value.
    # strict   - Boolean indicating what should happen when the object type is
    #            unrecognized. Returns nil on "false", raises an 'ArgumentError'
    #            on "true". Default false.
    #
    # Returns the (nilable) string name for the object type.
    sig { params(obj_type: T.nilable(T.any(Symbol, Integer)), strict: T::Boolean).returns(T.nilable(String)) }
    def object_type_to_str(obj_type, strict: false)
      return nil if obj_type.nil?
      case obj_type
      when :TYPE_BLOB, GitHub::Spokes::Proto::Types::V1::Object::Type::TYPE_BLOB
        "blob"
      when :TYPE_TREE, GitHub::Spokes::Proto::Types::V1::Object::Type::TYPE_TREE
        "tree"
      when :TYPE_COMMIT, GitHub::Spokes::Proto::Types::V1::Object::Type::TYPE_COMMIT
        "commit"
      when :TYPE_TAG, GitHub::Spokes::Proto::Types::V1::Object::Type::TYPE_TAG
        "tag"
      else
        raise ArgumentError, "invalid type #{obj_type.inspect}" if strict
        nil
      end
    end

    # Convert the string name of an object type to its corresponding object type
    # enum value.
    #
    # type_str - String name of the object type.
    # strict   - Boolean indicating what should happen when the type string is
    #            unrecognized. Returns nil on "false", raises an 'ArgumentError'
    #            on "true". Default true.
    #
    # Returns the (nilable) Symbol representing the object type.
    sig { params(type_str: T.nilable(String), strict: T::Boolean).returns(T.nilable(Symbol)) }
    def str_to_object_type(type_str, strict: true)
      case type_str.to_s
      when "blob"
        :TYPE_BLOB
      when "tree"
        :TYPE_TREE
      when "commit"
        :TYPE_COMMIT
      when "tag"
        :TYPE_TAG
      when ""
        nil
      else
        raise ArgumentError, "invalid type #{type_str.inspect}" if strict
        nil
      end
    end

    # Normalizes a path into a format acceptable to git. This will
    # remove leading slashes and convert empty or '.' paths to nil.
    #
    # path - The path String or nil.
    #
    # Return the normalized path String or nil.
    sig { params(path: T.nilable(String)).returns(T.nilable(String)) }
    def normalize_path(path)
      return if path.nil?

      path = path.b.sub(/\A\//, "")
      path = nil if path.empty? || path == "."
      path
    end

    # Given an integer (or nil) file mode, returns whether that mode corresponds
    # to a symlink type.
    #
    # mode - Integer mode or nil
    #
    # Return a boolean indicating whether the mode is a symlink mode.
    sig { params(mode: T.nilable(Integer)).returns(T::Boolean) }
    def symlink?(mode)
      !!mode && mode == 0120000
    end
  end
end
