# typed: strict
# frozen_string_literal: true

module Sponsors
  module BulkSponsorshipImports
    module Errors
      class AmountUnderMinimumComponent < ApplicationComponent
        extend T::Sig
        include Sponsors::BulkSponsorshipImports::Errors::ViewComponentMethods

        private

        sig { override.returns(String) }
        def test_selector
          "amount-under-minimum-error"
        end

        sig { override.returns(String) }
        def error_message
          "#{sponsorable_logins_count} of the maintainers you want to sponsor have minimum sponsorship amounts. " \
            "Please update your amount to meet their minimum:"
        end

        sig { override.returns(T::Array[String]) }
        def errored_login_messages
          amount_under_minimum_amounts_by_logins.map do |display_login, minimum_amount|
            "@#{display_login}, minimum amount $#{minimum_amount}"
          end
        end

        sig { returns(T::Hash[String, Integer]) }
        def amount_under_minimum_amounts_by_logins
          errored_rows.each_with_object({}) do |row, hash|
            login = row.sponsorable&.display_login || row.sponsorable_login
            hash[login] = row.min_amount.dollars.to_i
          end
        end
      end
    end
  end
end
