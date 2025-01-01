# typed: strict
# frozen_string_literal: true

module Billing
  module Interfaces
    module AddressLookupResult
      extend T::Helpers

      interface!

      sig { abstract.returns(T::Boolean) }
      def no_match?; end

      sig { abstract.returns(T::Boolean) }
      def suggested_match?; end

      sig { abstract.returns(T::Boolean) }
      def exact_match?; end

      sig { abstract.returns(T.nilable(String)) }
      def suggested_street; end

      sig { abstract.returns(T.nilable(String)) }
      def suggested_city; end

      sig { abstract.returns(T.nilable(String)) }
      def suggested_region; end

      sig { abstract.returns(T.nilable(String)) }
      def suggested_postal_code; end
    end
  end
end
