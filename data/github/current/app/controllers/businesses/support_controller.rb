# typed: true
# frozen_string_literal: true

class Businesses::SupportController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: %i(index)

  def index
    render "businesses/settings/support", locals: { entitlees: support_entitlees }
  end

  private

  memoize def support_entitlees
    this_business.support_entitlees.includes(:profile)
  end
end
