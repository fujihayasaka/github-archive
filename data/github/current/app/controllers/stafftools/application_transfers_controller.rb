# typed: true
# frozen_string_literal: true

class Stafftools::ApplicationTransfersController < StafftoolsController
  before_action :load_application
  before_action :ensure_user_exists
  before_action :ensure_target_exists, only: :create
  before_action :check_valid_target, only: :create

  def create
    if transfer_target != @app.owner
      if @app.transfer_ownership_to(transfer_target, requester: current_user, responder: current_user)
        flash[:notice] = "Transferred ownership of #{@app.name} to #{transfer_target.login}."
      else
        flash[:error] = "Failed to transfer ownership of #{@app.name} to #{transfer_target.login}."
      end

      redirect_to stafftools_user_application_path(@app.owner.login, @app)
    else
      flash[:error] = "You cannot transfer an application to its current owner."

      redirect_to stafftools_user_application_path(@app.owner.login, @app)
    end
  end

  def transfer_suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      business = @app.owner_enterprise_managed_business
      view = create_view_model(AutocompleteView, query: params[:q], with_orgs: true, exclude_suspended: true, business: business, businesses_only: business.present?)

      visible_suggestions = cap_filter.authorized_resources(view.suggestions)
      format.html_fragment do
        render partial: "users/autocomplete", formats: :html, locals: {
          view: view,
          suggestions: visible_suggestions
        }
      end
      format.html do
        return head :not_acceptable unless request.xhr?
        render partial: "users/autocomplete", locals: {
          view: view,
          suggestions: visible_suggestions
        }
      end
    end
  end

  private

  def ensure_target_exists
    unless transfer_target
      flash[:error] = "User #{params[:username]} not found."

      redirect_to stafftools_user_application_path(@app.owner.login, @app)
    end
  end

  def load_application
    @app = OauthApplication.find_by!(id: params[:application_id])
  end

  memoize def transfer_target
    User.find_by(login: params[:username])
  end

  def check_valid_target
    if !@app.valid_target?(transfer_target)
      flash[:error] = "This integration cannot be transferred to #{transfer_target.login} because #{transfer_target.login} does not belongs to the App Owner's Enterprise."

      redirect_to stafftools_user_application_path(@app.owner.login, @app)
    end
  end

end
