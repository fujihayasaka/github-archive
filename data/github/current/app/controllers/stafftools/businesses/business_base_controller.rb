# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class BusinessBaseController < StafftoolsController
      before_action :dotcom_required
      before_action :business_required

      layout "layouts/stafftools/business"

      DEFAULT_PAGE_SIZE = 30

      private

      def business_required
        render_404 unless this_business
      end

      memoize def this_business
        slug = params[:enterprise_slug] || params[:slug]
        ::Business.find_by(slug: slug)
      end
      helper_method :this_business

      def enterprise_managed_business_required
        render_404 unless this_business&.enterprise_managed_user_enabled?
      end

      def check_for_owners
        if this_business.owners.empty? &&
          this_business.invitations.pending.with_business_role(:owner).empty?
          if this_business.trial_cancelled?
            cancelled_trial = " as it is a cancelled trial"
            reinstate = " when reinstating the account"
          end

          flash.now[:error] = "This Enterprise account does not have any owners#{cancelled_trial}. \
            Please add or invite an owner for this enterprise#{reinstate}.".squish
        end
      end
    end
  end
end
