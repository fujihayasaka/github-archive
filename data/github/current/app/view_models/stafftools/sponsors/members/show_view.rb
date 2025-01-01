# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    module Members
      class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
        attr_reader :listing

        def can_unpublish_listing?
          return false unless listing.present?

          listing.unpublishable_by?(current_user)
        end

        def under_fraud_review?
          return false unless listing.present?
          listing.fraud_reviews.flagged.any?
        end
      end
    end
  end
end
