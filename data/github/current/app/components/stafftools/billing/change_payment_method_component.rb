# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class ChangePaymentMethodComponent < ApplicationComponent
      # user - a User or Organization
      # available_plan_options - an Array of Arrays for use with Rails' #options_for_select for showing a select
      #                          menu of options for changing the given user/organization's plan
      # current_term_end_date - Date for when the given user's current billing term will end; can be nil
      def initialize(user:, available_plan_options:, current_term_end_date:)
        @user = user
        @available_plan_options = available_plan_options
        @current_term_end_date = current_term_end_date
      end

      private

      attr_reader :user, :available_plan_options, :current_term_end_date

      def form_url
        if user.invoiced?
          pay_by_credit_card_stafftools_user_path(user)
        else
          pay_by_invoice_stafftools_user_path(user)
        end
      end
    end
  end
end
