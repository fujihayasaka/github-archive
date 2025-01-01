# typed: strict
# frozen_string_literal: true

module Sponsors
  module BulkSponsorshipImports
    module Errors
      class LockedSponsorshipComponent < ApplicationComponent
        extend T::Sig
        include Sponsors::BulkSponsorshipImports::Errors::ViewComponentMethods

        private

        sig { override.returns(String) }
        def test_selector
          "locked-sponsorship-error"
        end

        sig { override.returns(String) }
        def error_message
          noun = sponsorable_logins_count == 1 ? "maintainer" : "#{sponsorable_logins_count} maintainers"
          "You cannot sponsor the following #{noun} because an existing one-time sponsorship " \
            "is currently processing:"
        end
      end
    end
  end
end
