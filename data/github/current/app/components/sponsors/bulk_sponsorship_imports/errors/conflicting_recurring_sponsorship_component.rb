# typed: strict
# frozen_string_literal: true

module Sponsors
  module BulkSponsorshipImports
    module Errors
      class ConflictingRecurringSponsorshipComponent < ApplicationComponent
        extend T::Sig
        include Sponsors::BulkSponsorshipImports::Errors::ViewComponentMethods

        private

        sig { override.returns(String) }
        def test_selector
          "conflicting-recurring-sponsorship-error"
        end

        sig { override.returns(String) }
        def error_message
          noun = sponsorable_logins_count == 1 ? "maintainer" : "#{sponsorable_logins_count} maintainers"
          sponsor_description = sponsor.organization? ? "@#{sponsor}" : "You"
          contraction = sponsor.organization? ? "they're" : "you're"
          "#{sponsor_description} cannot sponsor the following #{noun} because #{contraction} already sponsoring them:"
        end
      end
    end
  end
end
