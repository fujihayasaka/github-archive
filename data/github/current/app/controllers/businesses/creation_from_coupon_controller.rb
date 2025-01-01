# typed: true
# frozen_string_literal: true

class Businesses::CreationFromCouponController < ApplicationController
  include SharedBusinessActions

  before_action :login_required
  before_action :dotcom_required
  before_action :non_emu_required
  before_action :ensure_coupon_is_self_serve_business_plus, except: [:check_slug, :destroy]

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Mysql5,
  ApplicationRecord::Collab,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Mysql2,
  ApplicationRecord::Copilot, only: [:new]

  javascript_bundle :businesses

  def new
    render "businesses/create_from_coupon", locals: {
      business: Business.new,
      organizations: selectable_organizations,
    }
  end

  def create
    if params[:gca_business].blank?
      flash[:error] = "You must accept the GitHub Customer Agreement to continue."
      return redirect_to new_enterprise_from_coupon_path(code: params[:code])
    end

    if params[:organization_login]
      org_to_attach = Organization.find_by(login: params[:organization_login])
      org_to_attach = nil unless selectable_organizations.include?(org_to_attach)
    end

    business_creator = Business::Creator.new(
      business_params: business_params.merge(
        can_self_serve: true,
        owners: [current_user],
        upgrade_initiated_from_organization_id: org_to_attach&.id,
        billing_email: current_user.email,
        seats: org_to_attach.present? ? org_to_attach.default_seats : 1,
        customer_attributes: business_params.fetch(:customer_attributes, {}).merge(
          billing_type: "card"
        )),
      actor: current_user
    )

    if business_creator.valid?
      business_creator.save!
      business = business_creator.business
      business.enable_self_serve_payments(skip_billing: true)
      business.update!(plan_duration: org_to_attach.plan_duration) if org_to_attach.present?
      business.initiate_creation_from_coupon(current_user, coupon_code: params[:code])
      if GitHub.flipper[:org_upgrade_and_coupon_vnext_enterprise_onboarding].enabled?(current_user)
        business.customer.onboard_to_all_billing_platform_products(previous_customer_id: org_to_attach&.customer&.id.to_s || "")
      end
      org_to_attach.upgrade_to_enterprise_in_progress!(business) if org_to_attach.present?
      # will probably want to email the user to let them know they've started redeeming the coupon?
      BusinessCreationInitiatedFromCouponDeletionJob.set(wait: 1.day).perform_later(business)

      redirect_to redeem_coupon_path(code: params[:code], id: business.slug)
    else
      flash[:error] = "Failed to create enterprise account: #{business_creator.error_message}."
      redirect_to new_enterprise_from_coupon_path(code: params[:code])
    end
  end

  def destroy
    return render_404 unless business = Business.find_by(slug: params[:slug])
    return render_404 unless business.owners.include?(current_user)
    return render_404 unless business.creation_initiated_from_coupon?

    if business.cancel_creation_from_coupon(current_user)
      flash[:notice] = "Your coupon redemption has been cancelled."
      redirect_to find_coupon_path
    else
      flash[:error] = "Failed to cancel coupon redemption. Please try again later or contact support."
      redirect_to :back
    end
  end

  private

  def business_params
    params.require(:business).permit(
      :name,
      :slug,
    )
  end

  def ensure_coupon_is_self_serve_business_plus
    coupon = Coupon.find_by(code: params[:code])
    render_404 if coupon&.expired? || !coupon&.self_serve_business_plus_coupon?
  end

  def resource_for_conditional_access
    self
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def selectable_organizations
    current_user.owned_organizations.select { |org| org.selectable_for_business_created_from_coupon?(current_user) }
  end
end
