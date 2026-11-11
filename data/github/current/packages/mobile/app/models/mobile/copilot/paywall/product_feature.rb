# typed: strict
# frozen_string_literal: true

module Mobile
  module Copilot
    module Paywall
      class ProductFeature
        sig { params(hash: T::Hash[Symbol, T.untyped]).returns(ProductFeature) }
        def self.from_hash(hash)
          new(title: hash[:title].to_s)
        end

        sig { returns(String) }
        attr_reader :title

        sig do
          params(
            title: String
          ).void
        end
        def initialize(title:)
          @title = title
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_hash
          { title: }
        end

        sig { params(other: ProductFeature).returns(T::Boolean) }
        def eql?(other)
          self.class == other.class && title == other.title
        end
        alias :== eql?
      end
    end
  end
end
