# typed: true
# frozen_string_literal: true

class Stafftools::Users::TermsOfServiceRecordsController < StafftoolsController
  before_action :ensure_user_exists
  before_action :ensure_org_not_user
  before_action :ensure_note_exists, only: [:update]
  before_action :dotcom_required

  layout "stafftools/organization"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    render "stafftools/users/terms_of_service_records/show", locals: { organization: this_user }
  end

  def update
    # we need to save these before we update the terms of service
    tos_changed = this_user.org_is_on_business_tos? && !Organization::TermsOfService::BUSINESS_TERMS_OF_SERVICE_TYPES.include?(params[:organization][:terms_of_service_type])
    delete_related_records if tos_changed && !this_user.has_commercial_interaction_restriction?(feature_type: :terms_of_service_change)

    if this_user.terms_of_service.update(**terms_of_service_params)
      flash[:notice] = "Updated the terms of service."
    else
      flash[:error] = "Failed to update terms of service."
    end

    redirect_to stafftools_user_terms_of_service_record_path(this_user)
  end

  private

  def delete_related_records
    this_user.remove_billing_information(actor: current_user, skip_validations: true)
    user_trade_screening_record.destroy(actor: current_user, reason: AccountScreeningProfile::TOS_CHANGE_BY_STAFF_REASON)
  end

  def terms_of_service_params
    {
      type: params[:organization][:terms_of_service_type],
      actor: current_user,
      company_name: params[:organization][:company_name],
      staff_actor: true,
      change_note: params[:organization][:terms_of_service_change_note],
    }
  end

  # Target user trade screening record for deleting when ToS changes
  sig { returns(AccountScreeningProfile) }
  def user_trade_screening_record
    this_user.trade_screening_record
  end

  sig { void }
  def ensure_note_exists
    return unless params[:organization][:terms_of_service_change_note].blank?

    flash[:error] = "Change note is required."
    redirect_to stafftools_user_terms_of_service_record_path(this_user)
  end
end
