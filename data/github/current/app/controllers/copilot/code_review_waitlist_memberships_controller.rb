# typed: true
# frozen_string_literal: true

class Copilot::CodeReviewWaitlistMembershipsController < ApplicationController
  before_action :login_required
  before_action :dotcom_required
  before_action :ensure_not_proxima
  before_action :ensure_feature_enabled

  stylesheet_bundle :signup_copilot

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:new, :show]

  def new
    render_form
  end

  def create
    membership = EarlyAccessMembership.new(
      member: nominee,
      actor_id: current_user.id,
      feature_slug: beta.feature_slug,
      survey: beta.survey,
      can_onboard: actor_is_admin?,
    )

    if membership.save
      redirect_to copilot_code_review_waitlist_membership_path(membership)
    else
      set_error_flash(membership)
      render_form
    end
  end

  def show
    membership = EarlyAccessMembership.find_by!(id: params[:id], actor_id: current_user.id)

    render "copilot/code_review_waitlist_memberships/show", locals: {
      member: membership.member,
    }
  end

  private

  def set_error_flash(membership)
    errors_with_messages_we_care_about = membership.errors.full_messages_for(:member)
    errors_with_messages_we_care_about += membership.errors.full_messages_for(:member_id)

    if errors_with_messages_we_care_about.presence
      flash.now[:error] = errors_with_messages_we_care_about.to_sentence
    else
      flash.now[:error] = "Something went wrong. Please try again."
    end
  end

  sig { returns(T::Boolean) }
  def actor_is_admin?
    return false if nominee.nil?
    return true if nominee == current_user

    T.cast(nominee, Organization).adminable_by?(current_user)
  end

  def render_form
    context_region_title "Copilot-powered code reviews waitlist"

    render "copilot/code_review_waitlist_memberships/new", locals: {
      has_copilot_individual: copilot_user.has_ci_access?,
      organizations: copilot_user.copilot_organizations,
      preview_terms: beta.preview_terms,
      has_copilot_standalone_business: has_copilot_standalone_business?,
    }
  end

  sig { returns(T.nilable(T.any(::User, ::Organization))) }
  memoize def nominee
    return current_user if copilot_user.has_ci_access?

    return nil unless params[:member_id].present?

    org = ::Organization.find_by(id: params[:member_id])
    return nil unless org&.member?(current_user)

    org
  end

  def ensure_not_proxima
    render_404 if GitHub.multi_tenant_enterprise?
  end

  def target_for_conditional_access
    # This is safe due to :login_required
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    logged_in? ? current_user : :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  memoize def beta
    ::Copilot::CodeReviewBeta.new
  end

  def ensure_feature_enabled
    render_404 unless current_user.feature_enabled?(:copilot_code_review_waitlist)
  end

  def copilot_user
    T.must_because(current_copilot_user_v2) { "before_action login_required" }
  end

  sig { returns(T::Boolean) }
  def user_member_of_nominee?
    return false unless nominee.present?
    return true if current_user == nominee

    T.cast(nominee, Organization).member?(current_user)
  end

  sig { returns(T::Boolean) }
  def has_copilot_standalone_business?
    copilot_standalone_businesses = copilot_user.copilot_businesses.select(&:copilot_standalone?)
    copilot_standalone_businesses.present?
  end
end
