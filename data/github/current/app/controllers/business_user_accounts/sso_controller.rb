# typed: true
# frozen_string_literal: true

class BusinessUserAccounts::SsoController < ApplicationController
  before_action :business_owner_required
  before_action :dotcom_required
  before_action :saml_enabled_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  def index
    redirect_to enterprise_person_sso_enterprise_path(this_business, business_user_account.user)
  end

  private

  # Safe because :business_owner_required ensures this_business is not nil (or else 404)
  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_business # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_business
  end

  def this_business
    business_user_account.business
  end

  def business_owner_required
    render_404 unless business_user_account.business.owner?(current_user)
  end

  memoize def business_user_account
    BusinessUserAccount.find(params[:id])
  end

  def query_param
    params[:query]
  end

  def saml_enabled_required
    render_404 unless this_business.saml_sso_enabled?
  end
end
