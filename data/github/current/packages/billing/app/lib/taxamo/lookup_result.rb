# typed: strict
# frozen_string_literal: true

module Taxamo
  class LookupResult < T::Struct
    include Billing::Interfaces::AddressLookupResult

    class SimilarMatch < T::Struct
      const :street_name, String
      const :city, String
      const :postal_code, String
      const :county, T.nilable(String)
      const :region, String
    end

    class Error < T::Struct
      const :messages, T::Array[String]
      const :error_code, String
    end

    prop :exact_match, T::Boolean, default: false
    prop :match, T.nilable(SimilarMatch)
    prop :error, T.nilable(Error)
    prop :lookup_failed, T::Boolean, default: false

    sig { override.returns(T::Boolean) }
    def no_match?
      (!exact_match || !!error) && match.nil?
    end

    sig { override.returns(T::Boolean) }
    def suggested_match?
      !exact_match && match.present?
    end

    sig { override.returns(T::Boolean) }
    def exact_match?
      exact_match
    end

    sig { override.returns(T.nilable(String)) }
    def suggested_street
      match&.street_name
    end

    sig { override.returns(T.nilable(String)) }
    def suggested_city
      match&.city
    end

    sig { override.returns(T.nilable(String)) }
    def suggested_region
      match&.region
    end

    sig { override.returns(T.nilable(String)) }
    def suggested_postal_code
      match&.postal_code
    end

    sig { override.returns(T::Boolean) }
    def lookup_failed?
      lookup_failed
    end
  end
end
