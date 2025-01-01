# typed: true
# frozen_string_literal: true

module Stafftools::Billing::Concerns::ZuoraWebhooksMethods
  extend ActiveSupport::Concern
  extend T::Helpers
  include Kernel

  requires_ancestor { ApplicationController }

  def show_zuora_webhooks(customers)
    zuora_account_ids = customers.map(&:zuora_account_id).compact
    webhooks =
    if zuora_account_ids.present?
      ::Billing::ZuoraWebhook
      .where(account_id: zuora_account_ids)
      .order(id: :desc)
    else
      ::Billing::ZuoraWebhook.none
    end.paginate(page: current_page, per_page: self.class.const_get(:PER_PAGE))
    render "stafftools/billing/zuora_webhooks/index", locals: { webhooks: webhooks, zuora_account_ids: zuora_account_ids }
  end

  included do |base|
    base.const_set :PER_PAGE, 20
  end
end
