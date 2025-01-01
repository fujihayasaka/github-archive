# typed: strict
# frozen_string_literal: true

class Businesses::AdvancedSecurity::CancelSubscriptionsController < ::Businesses::AdvancedSecurity::SelfServeController
  extend T::Sig
  include BillingSettingsHelper

  before_action :ensure_billing_enabled
  before_action :business_access_required
  before_action :ensure_self_serve_advanced_security

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
  only: [:show]

  sig { void }
  def show
    return render_404 unless request.xhr?

    expiration_date = this_business.advanced_security_subscription_item&.next_billing_date&.strftime("%B %-e, %Y")
    render "businesses/advanced_security/cancel_subscriptions/show", locals: { expiration_date: expiration_date }, layout: false
  end
end
