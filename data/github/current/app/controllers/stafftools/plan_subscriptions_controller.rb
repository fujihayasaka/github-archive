# typed: true
# frozen_string_literal: true

class Stafftools::PlanSubscriptionsController < StafftoolsController
  include BillingSettingsHelper

  before_action :ensure_user_exists
  before_action :ensure_billing_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    only: [:auto_pay]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    only: [:synchronization]

  def synchronization # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        if this_user.external_subscription?
          render partial: "stafftools/users/external_subscription_synchronization",
                 locals: { user: this_user }
        else
          head :ok, content_type: "text/html"
        end
      end
    end
  end

  def auto_pay # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        if this_user.has_billing_record?
          render partial: "stafftools/billing/auto_pay_settings", locals: { account: this_user }
        else
          head :ok, content_type: "text/html"
        end
      end
    end
  end

  private

  def billing_date
    begin
      if params[:billed_on].present? && (date = Date.strptime(params[:billed_on], "%F"))
        date if date > GitHub::Billing.today
      end
    rescue # rubocop:todo Lint/RescueException
      nil
    end
  end

end
