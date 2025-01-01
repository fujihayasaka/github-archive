# typed: strict
# frozen_string_literal: true

module Repositories
  module Contents
    class TreeEntry

      sig { returns(String) }
      attr_reader :oid, :path, :name

      sig { returns(Integer) }
      attr_reader :size, :mode

      sig { returns(Symbol) }
      attr_reader :type

      sig { returns(T.nilable(TreeEntry)) }
      attr_reader :symlink_target

      sig { returns(T.nilable(String)) }
      attr_reader :submodule_path

      sig { returns(T.nilable(String)) }
      attr_reader :submodule_url

      sig { returns(T.nilable(String)) }
      attr_reader :submodule_name

      alias_method :sha, :oid

      sig do
        params(
          type: Symbol,
          oid: String,
          path: String,
          name: String,
          mode: Integer,
          size: Integer,
          symlink_target: T.nilable(TreeEntry),
          submodule_path: T.nilable(String),
          submodule_url: T.nilable(String),
          submodule_name: T.nilable(String)
        ).void
      end
      def initialize(type:, oid:, path:, name:, mode:, size:, symlink_target: nil, submodule_path: nil, submodule_url: nil, submodule_name: nil)
        @type = type
        @oid = oid
        @path = path
        @name = name
        @mode = mode
        @size = size
        @symlink_target = symlink_target
        @submodule_path = submodule_path
        @submodule_url = submodule_url
        @submodule_name = submodule_name
      end

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        return false unless other.is_a?(TreeEntry)
        other.type == type &&
        other.oid == oid &&
        other.path == path &&
        other.name == name &&
        other.mode == mode &&
        other.size == size &&
        other.symlink_target == symlink_target &&
        other.submodule_path == submodule_path &&
        other.submodule_url == submodule_url &&
        other.submodule_name == submodule_name
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          type: type,
          oid: oid,
          path: path,
          name: name,
          mode: mode,
          size: size,
          symlink_target: symlink_target&.to_h,
          submodule_path: submodule_path,
          submodule_url: submodule_url,
          submodule_name: submodule_name
        }
      end
    end
  end
end
