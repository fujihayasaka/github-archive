# typed: true
# frozen_string_literal: true

class Businesses::TwoFactorSecureMethodsController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :updating_two_factor_requirement_required, only: :show

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot, only: [:show], optional: true

  def show
    respond_to do |format|
      return render_404 unless GitHub.two_factor_sms_enabled?

      format.html do
        render partial: "businesses/settings/security/two_factor/secure_methods_checkbox", locals: {
          business: this_business,
        }
      end
    end
  end
end
