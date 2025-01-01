# typed: strict
# frozen_string_literal: true

class Copilot::Workbench::DeploymentController < Copilot::Workbench::AbstractWorkbenchController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  allow_verified_fetch

  before_action :try_parse_json_params, only: [:update]
  before_action :require_workbench, only: [:update]

  sig { void }
  def update
    return render_404 unless maybe_workbench

    workbench = T.must(maybe_workbench)
    return render_404 unless workbench.runtime_app

    runtime_app = T.must(workbench.runtime_app)

    updated_fields = {}

    if params.key?(:visibility)
      original_visibility = runtime_app.visibility
      original_visibility_organization_id = runtime_app.visibility_organization_id
      new_visibility = params[:visibility]
      if new_visibility == "selected_orgs"
        new_visibility_organization_id = params[:visibility_organization_id]
        return render_404 unless new_visibility_organization_id.present?
        organization = Organization.find_by(id: new_visibility_organization_id)
        return render_404 unless organization
        # Also ensure that the user has access to it and didn't pass in a random org ID
        return render_404 unless organization.member?(current_user)
      end

      updated_fields[:visibility] = new_visibility
      updated_fields[:visibility_organization_id] = new_visibility_organization_id
    end

    if params.key?(:read_only_kv)
      read_only_kv = params[:read_only_kv]
      updated_fields[:read_only_kv] = read_only_kv
    end

    if updated_fields.any?
      runtime_app.update!(updated_fields)

      # perform operations after db update
      if params.key?(:visibility)
        SparkRuntime::AcaInterface.notify_settings_changes(current_user, workbench)

        SparkRuntime::AcaInterface.purge_auth_for_app(
          current_user,
          runtime_app.permanent_name) if needs_purge_auth?(original_visibility, new_visibility, original_visibility_organization_id, new_visibility_organization_id)
      end

      render json: updated_fields, status: :ok
    else
      render_404
    end
  end

  private

  sig do
    params(
      original_visibility: String,
      new_visibility: String,
    ).returns(T::Boolean)
  end
  def needs_purge_auth_old?(original_visibility, new_visibility)
    return false if original_visibility == new_visibility

    new_visibility != "github"
  end

  sig do
    params(
      original_visibility: String,
      new_visibility: String,
      original_organization_id: T.nilable(Integer),
      new_organization_id: T.nilable(Integer),
    ).returns(T::Boolean)
  end
  def needs_purge_auth?(original_visibility, new_visibility, original_organization_id = nil, new_organization_id = nil)
    return false if original_visibility == new_visibility && original_organization_id == new_organization_id

    case original_visibility
    when "only_owner"
      # Starting at owner only: To any other auth: no purge necessary
      false
    when "github"
      # Starting at GitHub visible: To private: purge auth, To any org: purge auth
      new_visibility == "only_owner" || new_visibility == "selected_orgs"
    when "selected_orgs"
      # Starting at selected orgs: To private: purge auth, To GitHub: don't purge, To any other org: purge auth
      case new_visibility
      when "only_owner"
        true
      when "github"
        false
      when "selected_orgs"
        # Different org, so purge auth
        original_organization_id != new_organization_id
      else
        false
      end
    else
      false
    end
  end


  sig { returns T.nilable(Spark::Workbench) }
  memoize def maybe_workbench
    Spark::Workbench.for_uuid_string(current_user.id, params[:id])
  end

  sig { void }
  def require_workbench
    render_404 unless maybe_workbench
  end
end
