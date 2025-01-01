# typed: strict
# frozen_string_literal: true

module Sponsors
  module BulkSponsorshipImports
    module Errors
      class RowsOverLimitComponent < ApplicationComponent
        extend T::Sig
        include Sponsors::BulkSponsorshipImports::Errors::ViewComponentMethods

        private

        sig { override.returns(String) }
        def test_selector
          "rows-over-limit-error"
        end

        sig { override.returns(String) }
        def error_message
          "The maximum number of rows that can be imported at a time is " \
            "#{Sponsors::BulkSponsorshipValidator::MAX_SPONSORABLES}. Because of this " \
            "#{rows_over_limit_count} #{"row".pluralize(rows_over_limit_count)} " \
            "#{"has".pluralize(rows_over_limit_count)} been ignored."
        end

        sig { override.returns(T::Array[String]) }
        def errored_login_messages
          []
        end

        sig { returns(Integer) }
        def rows_over_limit_count
          errored_rows.size
        end
      end
    end
  end
end
