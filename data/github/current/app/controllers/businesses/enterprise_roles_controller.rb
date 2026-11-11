# typed: strict
# frozen_string_literal: true

class Businesses::EnterpriseRolesController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency

  before_action :custom_enterprise_roles_enabled
  before_action :read_enterprise_roles_required, only: [:index]
  before_action :write_enterprise_roles_required, except: [:index]
  allow_verified_fetch

  depends_on_clusters \
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    only: [:index, :new, :edit]

  class CustomRolesRoutePayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "customEnterpriseRolesRoute"
    end
    sig { params(this_business: Business, action: Symbol).void }
    def initialize(this_business, action:)
      @this_business = this_business
      @action = action
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        owner_type: "Enterprise",
        owner_id: T.let(@this_business, Business).id,
        owner_name: T.let(@this_business, Business).name,
        action: T.let(@action, Symbol),
        availablePermissions: {
          Enterprise: EnterpriseRoleFgps.fgps_payload_for_react(@this_business)
        }
      }
    end
  end

  sig { void }
  def index
    render "businesses/enterprise_roles/index", locals: { business: this_business, viewer_permissions: viewer_permissions }
  end

  sig { void }
  def new
    custom_roles_count = EnterpriseRole.custom_roles_for_enterprise(this_business).count
    custom_roles_limit = EnterpriseRole.custom_role_limit_for_enterprise(this_business)

    if custom_roles_count >= custom_roles_limit
      flash[:custom_role_banner] = {
        "message_segments" => ["Reached max of #{custom_roles_limit} custom roles."],
        "scheme" => "danger",
      }
      return redirect_to enterprise_roles_path
    end

    if this_business.feature_flag_enabled?(:azxp_role_creation_react, default: false)
      respond_with_react(
        payload: CustomRolesRoutePayload.new(this_business, action: :new),
        title: "Create a new custom enterprise role · #{this_business.name}",
        app_name: "custom-roles",
        page_data: {
          selected_link: :enterprise_role_management,
          sidebar: :people
        },
        layout: "layouts/react_business"
      )
    else
      render "businesses/enterprise_roles/new", locals: { business: this_business }
    end
  end

  sig { void }
  def create
    if current_business.feature_flag_enabled?(:azxp_role_creation_react, default: false)
      use_json = true
      begin
        role_data = JSON.parse(request&.body.read)
        name = role_data["name"].to_s.strip
        description = role_data["description"].to_s.strip
        fgps = role_data["fgps"] || []
        owner_id = current_business.id
        owner_type = "Business"

        custom_role_params = { name: name, description: description, owner_id: owner_id, owner_type: owner_type }
      rescue JSON::ParserError
        return render status: :unprocessable_entity, json: { success: false, error: "Invalid JSON format." }
      end
    else
      use_json = false
      custom_role_params = role_params
      fgps = params.dig(:role, :fgps)
    end

    custom_role = EnterpriseRole.new(custom_role_params)
    error_message = nil
    begin
      Permissions::CustomRoles.create!(custom_role, fgps: fgps)
    rescue Role::CustomRoleError => e
      validation_error = custom_role.errors.full_messages.to_sentence
      error_message = "#{validation_error.presence || "Something went wrong. Could not create the role at this time"}."
      Failbot.report!(e, app: "github")
    end

    if error_message
      GitHub.dogstats.increment("custom_role.created", tags: ["result:fail", "owner_type:business", "target_type:business"])
      flash[:custom_role_banner] = {
        "message_segments" => [error_message],
        "scheme" => "danger",
      }

      if use_json
        render status: :unprocessable_entity, json: { success: false, message: error_message }
      else
        redirect_to new_enterprise_role_path(this_business)
      end
    else
      GitHub.dogstats.increment("custom_role.created", tags: ["result:success", "owner_type:business", "target_type:business"])
      flash[:custom_role_banner] = {
        "message_segments" => ["Your new ", { bold: custom_role.display_name }, " custom role has been successfully created."],
        "scheme" => "success",
        "assign_role_path" => new_enterprise_role_assignment_path(this_business),
      }
      if use_json
        render status: :ok, json: { success: true }
      else
        redirect_to enterprise_roles_path
      end
    end
  end

  sig { void }
  def destroy
    error_message = nil
    begin
      role = EnterpriseRole.find_by!(id: params[:id], owner_id: this_business.id, owner_type: "Business")
      Permissions::CustomRoles.destroy!(role, current_user)
    rescue ActiveRecord::ActiveRecordError, ActiveRecord::RecordNotFound, Role::CustomRoleError
      error_message = "Something went wrong. Could not delete role at this time."
    end

    if error_message
      flash[:custom_role_banner] = {
        "message_segments" => [error_message],
        "scheme" => "danger",
      }
    else
      flash[:custom_role_banner] = {
        "message_segments" => [{ bold: role.display_name }, " role was successfully deleted."],
        "scheme" => "success",
      }
    end
    redirect_to enterprise_roles_path
  end

  sig { void }
  def fgp_metadata  # rubocop:todo GitHub/UseRestfulActions
    render json: EnterpriseRoleFgps.new.available_fgps(this_business).index_by(&:label)
  end

  sig { void }
  def edit
    begin
      role = EnterpriseRole.find_by!(id: params[:id], owner_id: current_business.id, owner_type: "Business")
      assignment_counts = UserRole.where(target_type: "Business", target_id: current_business.id, role_id: role.id).group(:actor_type).count
    rescue
      flash[:custom_role_banner] = {
        "message_segments" => ["Something went wrong. Could not find the role."],
        "scheme" => "danger",
      }
      redirect_to enterprise_roles_path
    else
      render "businesses/enterprise_roles/edit", locals: { business: current_business, role: role, assignment_counts: assignment_counts }
    end
  end

  sig { void }
  def update
    custom_role_params = role_params

    begin
      role = EnterpriseRole.find_by!(id: params[:id], owner_id: current_business.id, owner_type: "Business")
      new_fgps = params[:role].delete(:fgps) || []
      Permissions::CustomRoles.update!(role, role_params: custom_role_params, fgps: new_fgps, actor: current_user)
    rescue ActiveRecord::RecordNotFound => e
      error_message = "Something went wrong. Could not update the role at this time."
    rescue Role::CustomRoleError => e
      validation_error = T.must(role).errors.full_messages.to_sentence
      error_message = "#{validation_error.presence || "Something went wrong. Could not update the role at this time"}."

      Failbot.report!(e, app: "github")
    ensure
      if error_message
        GitHub.dogstats.increment("custom_role.updated", tags: ["result:fail", "owner_type:business", "target_type:business"])
        flash[:custom_role_banner] = {
          "message_segments" => [error_message],
          "scheme" => "danger",
        }
        redirect_to edit_enterprise_role_path
      else
        GitHub.dogstats.increment("custom_role.updated", tags: ["result:success", "owner_type:business", "target_type:business"])
        flash[:custom_role_banner] = {
          "message_segments" => [{ bold: T.must(role).display_name }, " role was successfully updated."],
          "scheme" => "success",
        }
        redirect_to enterprise_roles_path
      end
    end
  end

  private

  sig { void }
  def custom_enterprise_roles_enabled
    render_404 unless this_business&.custom_enterprise_roles_supported?
  end

  sig { void }
  def read_enterprise_roles_required
    render_404 unless viewer_permissions[:read]
  end

  sig { void }
  def write_enterprise_roles_required
    render_404 unless viewer_permissions[:write]
  end

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  memoize def viewer_permissions
    return {} unless current_user && this_business

    permissions = Authz.domain.check_multiple_permissions(
      current_user,
      [:read_enterprise_custom_enterprise_role, :write_enterprise_custom_enterprise_role],
      this_business,
    )
    {
      read: permissions[:read_enterprise_custom_enterprise_role],
      write: permissions[:write_enterprise_custom_enterprise_role],
    }
  end

  sig { returns(ActionController::Parameters) }
  def role_params
    strip_params(:name)

    params.
      require(:role).
      permit(:name, :description, fgps: []).
      merge(owner_id: current_business.id, owner_type: "Business").
      except(:fgps)
  end

  sig { params(keys: T.untyped).void }
  def strip_params(*keys)
    keys.each { |key| params[:role][key]&.strip! }
  end
end
