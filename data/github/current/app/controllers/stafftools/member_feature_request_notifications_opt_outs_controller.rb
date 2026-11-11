# typed: true
# frozen_string_literal: true

class Stafftools::MemberFeatureRequestNotificationsOptOutsController < StafftoolsController
  before_action :dotcom_required
  before_action :entity_required

  def update
    if params[:opt_out_of_member_feature_request_notifications] == "on"
      entity.opt_out_of_member_feature_request_notifications(actor: current_user)
      flash[:notice] = "Opted #{entity} out of member feature request notifications."
    else
      entity.opt_in_to_member_feature_request_notifications(actor: current_user)
      flash[:notice] = "Opted #{entity} in to member feature request notifications."
    end
    redirect_to redirect_path
  end

  private

  def entity_required
    render_404 unless entity.present?
  end

  memoize def this_business
    ::Business.find_by(slug: params[:slug]) if params[:slug].present?
  end

  memoize def this_user
    super if super.is_a?(Organization)
  end

  memoize def entity
    this_business || this_user
  end

  def redirect_path
    if entity.is_a?(Business)
      stafftools_enterprise_path(entity)
    elsif entity.is_a?(Organization)
      stafftools_user_overview_path(entity)
    end
  end
end
