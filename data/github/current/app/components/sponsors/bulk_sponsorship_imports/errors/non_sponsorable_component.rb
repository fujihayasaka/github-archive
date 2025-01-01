# typed: strict
# frozen_string_literal: true

module Sponsors
  module BulkSponsorshipImports
    module Errors
      class NonSponsorableComponent < ApplicationComponent
        extend T::Sig
        include Sponsors::BulkSponsorshipImports::Errors::ViewComponentMethods

        private

        sig { override.returns(String) }
        def test_selector
          "non-sponsorable-error"
        end

        sig { override.returns(String) }
        def error_message
          noun = sponsorable_logins_count == 1 ? "maintainer" : "#{sponsorable_logins_count} maintainers"
          "You cannot sponsor the following #{noun}. They may not use " \
            "GitHub Sponsors or you may have misspelled their name:"
        end
      end
    end
  end
end
