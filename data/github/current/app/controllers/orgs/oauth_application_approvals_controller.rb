# typed: true
# frozen_string_literal: true

class Orgs::OauthApplicationApprovalsController < Orgs::Controller
  before_action :organization_read_or_outside_collaborator_required, only: [:request_approval]
  before_action :manage_org_oauth_policy_permission_required, only: [:show, :set_state]
  before_action :sudo_filter, except: :request_approval

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:show]

  preload_features [:first_party_oauth_app_restrictions]

  def show
    unless this_organization.restricts_oauth_applications?
      redirect_to settings_org_oauth_application_policy_path(this_organization)
      return
    end

    @approval = this_organization.
                  oauth_application_approvals.
                  find_by_application_id(params[:application_id])

    @application = oauth_app

    view = create_view_model(
      Oauth::AuthorizeView,
      approval: @approval,
      application: @application
    )

    if @application.blockable_client_app?
      if current_organization.first_party_oauth_app_restrictions_enabled?
        render "orgs/oauth_application_approvals/show_first_party_app", locals: { view: view }
      else
        render_404
      end
    else
      render "orgs/oauth_application_approvals/show_third_party_app", locals: { view: view }
    end
  end

  def request_approval # rubocop:todo GitHub/UseRestfulActions
    this_organization.request_oauth_application_approval(oauth_app, requestor: current_user)

    if request.xhr?
      head 200
    else
      redirect_to org_application_approval_path(this_organization, oauth_app)
    end
  end

  def set_state # rubocop:todo GitHub/UseRestfulActions
    approval = nil
    error = nil
    notice = nil

    begin
      case params[:state]
      when "approved"
        approval = this_organization.approve_oauth_application(oauth_app, approver: current_user)
        notice = "#{oauth_app.name} is authorized to access this organization’s resources"
      when "denied"
        approval = this_organization.deny_oauth_application(oauth_app, actor: current_user)
        notice = "#{oauth_app.name} is denied access this organization’s resources"
      when "blocked"
        begin
          approval = this_organization.block_oauth_application(application: oauth_app, actor: current_user)
          notice = "#{oauth_app.name} is blocked from accessing this organization’s resources"
        rescue ActiveRecord::RecordInvalid
          error = "You cannot block this application."
        end
      when "unblocked"
        approval = this_organization.unblock_oauth_application(application: oauth_app, actor: current_user)
        notice = "#{oauth_app.name} is enabled to access this organization’s resources"
      end
    rescue ActiveRecord::RecordNotUnique
      error = "This application has already been updated in this organization"
    end

    if params[:flash]
      if notice
        flash[:notice] = notice
      elsif error
        flash[:error] = error
      end
    end

    if request.xhr?
      render json: { approval_state: approval.try(:state) }, status: 200
    else
      redirect_to org_application_approval_path(this_organization, oauth_app)
    end
  end

  private

  def oauth_app # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @oauth_app ||= OauthApplication.find(params[:application_id])
  end
end
