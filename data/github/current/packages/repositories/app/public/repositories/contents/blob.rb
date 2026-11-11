# typed: strict
# frozen_string_literal: true

module Repositories
  module Contents
    class Blob

      sig { returns(String) }
      attr_reader :oid

      sig { returns(String) }
      attr_reader :path

      sig { returns(Integer) }
      attr_reader :mode

      sig { returns(String) }
      attr_reader :contents

      sig { returns(Integer) }
      attr_reader :size

      sig { returns(T.nilable(Repositories::Contents::Blob)) }
      attr_reader :symlink_target

      sig { returns(String) }
      attr_reader :name

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      attr_reader :content_encoding

      sig do
        params(
          oid: String,
          path: String,
          mode: Integer,
          contents: String,
          size: Integer,
          symlink_target: T.nilable(Repositories::Contents::Blob),
          name: T.nilable(String),
          content_encoding: T.nilable(T::Hash[Symbol, T.untyped])
        ).void
      end
      def initialize(oid:, path:, mode:, contents:, size:, symlink_target: nil, name: nil, content_encoding: nil)
        @oid = oid
        @path = path
        @mode = mode
        @contents = contents
        @size = size
        @symlink_target = symlink_target
        @name = T.let(name || File.basename(path), String)

        @content_encoding = T.let(content_encoding || GitRPC::Encoding.guess(contents.frozen? ? contents.dup : contents), T.nilable(T::Hash[Symbol, T.untyped]))
      end

      sig { returns(T::Boolean) }
      def truncated?
        size > contents.size
      end

      sig { returns(T::Boolean) }
      def binary?
        if @content_encoding.nil?
          return true
        end

        @content_encoding[:type] == :binary
      end

      sig { returns(T.untyped) }
      def encoding
        if @content_encoding.nil?
          return nil
        end

        @content_encoding[:encoding]
      end

      sig { params(other: Object).returns(T::Boolean) }
      def ==(other)
        return false unless other.is_a?(self.class)

        oid == other.oid &&
          path == other.path &&
          mode == other.mode &&
          contents == other.contents &&
          size == other.size &&
          symlink_target == other.symlink_target &&
          name == other.name &&
          content_encoding == other.content_encoding
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          oid: oid,
          path: path,
          mode: mode,
          contents: contents,
          size: size,
          symlink_target: symlink_target&.to_h,
          name: name,
          content_encoding: content_encoding
        }
      end
    end
  end
end
