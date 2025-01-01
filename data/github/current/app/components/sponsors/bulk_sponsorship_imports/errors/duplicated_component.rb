# typed: strict
# frozen_string_literal: true

module Sponsors
  module BulkSponsorshipImports
    module Errors
      class DuplicatedComponent < ApplicationComponent
        extend T::Sig
        include Sponsors::BulkSponsorshipImports::Errors::ViewComponentMethods

        private

        sig { override.returns(String) }
        def test_selector
          "duplicated-error"
        end

        sig { override.returns(String) }
        def error_message
          verb = sponsorable_logins_count == 1 ? "was" : "were"
          "You cannot sponsor the same maintainer more than once. #{pluralize(sponsorable_logins_count, "maintainer")} " \
            "#{verb} found at least twice:"
        end

        sig { override.returns(T::Array[String]) }
        memoize def sponsorable_logins
          duplicated_logins = errored_rows.map { |row| row.sponsorable&.display_login || row.sponsorable_login }

          duplicated_logins.each_with_object([]) do |duplicated_login, array|
            normalized_unique_logins = array.map(&:downcase)
            array << duplicated_login if normalized_unique_logins.exclude?(duplicated_login.downcase)
          end
        end
      end
    end
  end
end
