# typed: true
# frozen_string_literal: true

module Stafftools
  module Users
    module Billing
      class SpendingLimitsController < Stafftools::Users::BillingController
        depends_on_clusters ApplicationRecord::Mysql1,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Ballast,
          ApplicationRecord::Collab,
          ApplicationRecord::Mysql2,
          ApplicationRecord::Mysql5,
          ApplicationRecord::Billing,
          ApplicationRecord::Repositories,
          ApplicationRecord::NotificationsEntries,
          ApplicationRecord::IssuesPullRequests,
          only: [:index]

        depends_on_clusters ApplicationRecord::Copilot,
          only: [:index],
          optional: true

        def index
          render "stafftools/billing/spending_limit/index", locals: { user: this_user }
        end

        def update
          unless ::Billing::Budget.configurable?(owner)
            flash[:error] = "User does not have a configurable spending limit"
            return redirect_to :back
          end

          unless ::Billing::Budget.valid_budget_group?(params[:budget_group])
            flash[:error] = "Unknown budget group: '#{params[:budget_group]}'"
            return redirect_to :back
          end

          unless owner.has_valid_payment_method?(feature_type: :noncommercial)
            flash[:error] = "You can't increase spending limits until you set up a valid payment method"
            return redirect_to :back
          end

          budget = owner.budget_for(group: params[:budget_group])
          budget.configure(
            enforce_spending_limit: params[:enforce_spending_limit] == "true",
            limit: params[:spending_limit],
          )

          if budget.errors.any?
            if budget.errors[:tiered_spending].present?
              flash[:error] = budget.errors[:tiered_spending].first
            else
              flash[:error] = "Unable to set a spending limit. Please check your payment method and limit"
            end
          else
            flash[:notice] = "Spending limit configuration has been updated for: '#{budget.product}'"
          end

          redirect_to :back
        end
      end
    end
  end
end
