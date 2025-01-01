# typed: true
# frozen_string_literal: true

class Businesses::AdminRolesController < Businesses::BusinessController
  include BusinessesHelper

  before_action :sudo_filter, only: %i(update)
  before_action :business_owner_required
  before_action :non_scim_managed_business_required

  def update
    errors = []
    new_role = params[:role]&.downcase&.to_sym
    admin = User.find_by login: admin_login_param
    errors << "Could not find user with login: #{admin_login_param}" unless admin.present?

    if admin.present?
      unless this_business.owner?(admin) || this_business.billing_manager?(admin)
        errors << "#{admin} is not an administrator of the enterprise account"
      end

      Ability.transaction do
        this_business.change_admin_role(admin, new_role: new_role, actor: current_user)
      rescue Business::UserHasTwoFactorDisabledError,
        Business::InvalidAdminStateError,
        Business::UserNotAnAdminError,
        Business::NoAdminsError,
        Business::UserHasNoExternalIdentityError,
        ArgumentError => error
        errors << error.message
      end
    end

    if errors.any?
      flash[:error] = errors.first
    else
      flash[:notice] = "#{admin} is now #{Business.admin_role_for_message(new_role)} of the enterprise account."
    end

    redirect_to enterprise_admins_path(this_business)
  end
end
