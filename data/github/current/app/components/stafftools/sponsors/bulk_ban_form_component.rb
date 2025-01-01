# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class BulkBanFormComponent < ApplicationComponent
      # filter - optional Hash of filters to pass along when submitting the bulk-ban form, to redirect the viewer
      #          back to the same list of members they were viewing; see
      #          Stafftools::Sponsors::MembersController::PERMITTED_FILTER_PARAMS for valid keys
      # query - optional String search query to redirect the viewer back to the same list of members
      # order - optional String sort order to redirect the viewer back to the same list of members; see
      #         Stafftools::SponsorsHelper::LISTING_SORT_OPTIONS for valid values
      def initialize(filter: {}, query: nil, order: nil)
        @filter = filter
        @query = query
        @order = order
      end

      private

      attr_reader :filter, :query, :order

      def render?
        GitHub.sponsors_enabled? && logged_in?
      end
    end
  end
end
