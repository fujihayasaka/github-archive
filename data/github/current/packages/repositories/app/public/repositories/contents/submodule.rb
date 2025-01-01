# typed: strict
# frozen_string_literal: true

module Repositories
  module Contents
    class Submodule

      sig { returns(String) }
      attr_reader :oid

      sig { returns(String) }
      attr_reader :path

      sig { returns(T.nilable(String)) }
      attr_reader :name

      sig { returns(T.nilable(String)) }
      attr_reader :url

      sig { params(oid: String, path: String, name: T.nilable(String), url: T.nilable(String)).void }
      def initialize(oid:, path:, name: nil, url: nil)
        @oid = oid
        @path = path
        @name = name
        @url = url
      end
    end
  end
end
