# typed: true
# frozen_string_literal: true

class Businesses::AdminsController < Businesses::BusinessController
  include BusinessesHelper
  include EnterpriseManagedUsersHelper

  before_action :business_owner_required
  before_action :non_scim_managed_business_required, except: %i(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: %i(index)

  def index
    query_args = parse_query_string(query_param,
      filter_map: BusinessesHelper::ADMINS_QUERY_FILTERS,
    )
    admins = this_business
      .admins(query: query_args[:query],
        role: query_args[:role],
        organization_logins: query_args[:organizations],
        two_factor: query_args[:two_factor_status]&.to_sym,
      )
      .includes(:profile)
      .paginate(page: current_page)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "businesses/admins/list", locals: {
            query: query_param,
            role: role_filter,
            view: create_view_model(Businesses::Admins::ListView,
              business: this_business,
              admins: admins,
            ),
          }
        else
          render "businesses/admins/index", locals: {
            query: query_param,
            role: role_filter,
            admins: admins,
          }
        end
      end
    end
  end

  def create
    return render_404 unless GitHub.bypass_business_member_invites_enabled?

    errors = []
    if GitHub.site_admin_role_managed_externally?
      errors << this_business.external_auth_system_owner_instructions(operation: :add)
    else
      owner = User.find_by login: admin_login_param
      errors << "Could not find user with login: #{admin_login_param}" unless owner.present?

      if owner.present?
        begin
          this_business.add_owner(owner, actor: current_user)
        rescue Business::UserHasTwoFactorDisabledError,
          Business::UserHasNoExternalIdentityError,
          Business::InvalidAdminStateError => error
          errors << error.message
        end
      end
    end

    if errors.any?
      error = errors.first
      respond_to do |wants|
        wants.html do
          flash[:error] = error
          redirect_to enterprise_admins_path(this_business)
        end
        wants.json do
          render json: { error: error }
        end
      end
    else
      respond_to do |wants|
        wants.html do
          redirect_to enterprise_admins_path(this_business),
            notice: "#{admin_login_param} is now an owner"
        end
        wants.json do
          admin_list_item = render_to_string \
            partial: "businesses/admins/admin",
            formats: [:html],
            locals: {
              business: this_business,
              admin: owner,
              role: :owner,
              user_link: user_path(owner)
            }

          render json: { html: admin_list_item }
        end
      end
    end
  end

  def destroy
    errors = []
    if GitHub.site_admin_role_managed_externally?
      errors << this_business.external_auth_system_owner_instructions(operation: :remove)
    else
      admin = User.find_by login: admin_login_param

      if admin.present?
        if this_business.owner?(admin)
          role = Business::OWNER_ROLE
          begin
            this_business.remove_owner(admin, actor: current_user)
          rescue Business::NoAdminsError
            errors << "You cannot remove the last owner of the enterprise account."
          end
        elsif this_business.billing_manager?(admin)
          role = Business::BILLING_MANAGER_ROLE
          this_business.billing.remove_manager(admin, actor: current_user)
        end
      end
    end

    if errors.any? || !admin.present?
      errors << "Could not find user with login: #{admin_login_param}" unless admin.present?
      error = errors.first
      if request.xhr?
        render plain: error, status: :bad_request
      else
        flash[:error] = error
        redirect_to enterprise_admins_path(this_business)
      end
    else
      if request.xhr?
        head :ok
      else
        if current_user == admin
          # Current user removed themselves as an owner
          redirect_to this_business.member?(current_user) ? enterprise_path(this_business) : home_path,
            notice: "You are no longer #{Business.admin_role_for_message(role)} of #{this_business.name}."
        else
          redirect_to enterprise_admins_path(this_business),
            notice: "You've removed #{admin.display_login} as #{::Business.admin_role_for_message(role)} of #{this_business.name}."
        end
      end
    end
  end

  private

  def role_filter
    params[:role]
  end
end
