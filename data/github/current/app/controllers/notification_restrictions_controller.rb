# typed: true
# frozen_string_literal: true

class NotificationRestrictionsController < ApplicationController
  include BusinessesHelper
  include VerifiableDomainsHelper

  before_action :verifiable_domains_required
  before_action :login_required
  before_action :owner_required
  before_action :owner_admin_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    only: %i(show)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    respond_to do |format|
      format.html do
        render "notification_restrictions/show",
          locals: {
            owner: owner
          },
          layout: false
      end
    end
  end

  def update
    begin
      result = if params[:restrict_notifications] == "on"
        owner.enable_notification_restrictions(actor: current_user, force: owner.is_a?(Business))
      else
        owner.disable_notification_restrictions(actor: current_user)
      end
    rescue Configurable::RestrictNotificationDelivery::PlanUnsupportedError,
      Configurable::RestrictNotificationDelivery::AlreadySetOnEnterpriseError,
      Configurable::RestrictNotificationDelivery::NoVerifiedDomainsError,
      Configurable::RestrictNotificationDelivery::SmtpNotConfiguredError => error
      flash[:error] = error.message
    end

    if result
      flash[:notice] = "Notification restrictions settings successfully updated."
    else
      flash[:error] ||= "An error occurred when modifying notification restriction for #{display_value_for(owner)}"
    end

    redirect_to :back
  end

  private

  def display_value_for(owner)
    case owner
    when Business
      owner.slug
    when Organization
      owner.display_login
    end
  end

  def verifiable_domains_required
    render_404 unless GitHub.verified_domains_enabled?
  end

  memoize def owner
    if organization_login_param.present?
      Organization.find_by login: organization_login_param
    elsif business_slug_param.present?
      Business.find_by slug: business_slug_param
    end
  end

  def owner_required
    render_404 unless owner
  end

  def owner_admin_required
    render_404 unless owner.adminable_by?(current_user)
  end

  def business_slug_param
    params[:slug].presence&.to_s
  end

  def organization_login_param
    params[:org].presence&.to_s
  end

  # This pattern is safe because of owner_required
  def target_for_conditional_access
    return :no_target_for_conditional_access unless owner # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    owner
  end
end
