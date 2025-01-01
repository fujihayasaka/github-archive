# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    class Entry < ::Contentful::Entry
      extend T::Sig
      extend T::Helpers
      abstract!

      sig { abstract.returns(String) }
      def self.content_type; end

      sig { abstract.returns(::Contentful::Client) }
      def self.contentful_client; end

      sig { returns(T.nilable(T::Array[String])) }
      def self.sparse_fields_for_index; end

      sig { returns(T.nilable(String)) }
      def self.category_slug; end
    end
  end
end
