# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::IntegrationsController < Stafftools::Businesses::BusinessBaseController

  def index
    @integrations = this_business.integrations.
      order("integrations.name asc").paginate(page: params[:page])

    render "stafftools/businesses/integrations/index"
  end

  def show
    render "stafftools/businesses/integrations/show", locals: { view: show_view }
  end

  def rename # rubocop:todo GitHub/UseRestfulActions
    integration.name = params[:name]
    if integration.save
      flash[:notice] = "Name successfully updated."
    else
      flash[:error] = integration.errors.full_messages.join(". ")
    end
    redirect_to stafftools_business_app_path(id: integration.slug)
  end

  def update_creation_limit # rubocop:todo GitHub/UseRestfulActions
    this_business.set_custom_applications_limit(application_type: Integration, limit: params[:creation_limit])

    flash[:notice] = "Creation limit updated successfully."
    redirect_to stafftools_business_apps_path(business_id: this_business.slug)
  end

  def revoke_public_keys # rubocop:todo GitHub/UseRestfulActions
    RevokeIntegrationPublicKeysJob.perform_later(integration, Time.zone.now.to_i)

    flash[:notice] = "A job has been enqueued to revoke existing keys."
    redirect_to stafftools_business_app_path(id: integration.slug)
  end

  def suspend # rubocop:todo GitHub/UseRestfulActions
    if integration.suspend(actor: current_user, reason: params[:reason])
      flash[:notice] = "Integration #{integration.slug} has been suspended."
    else
      flash[:error] = "App suspension has failed. Please try again."
    end

    redirect_to stafftools_business_app_path(id: integration.slug)
  end

  def unsuspend # rubocop:todo GitHub/UseRestfulActions
    if integration.unsuspend(actor: current_user)
      flash[:notice] = "Integration #{integration.slug} has been unsuspended."
    else
      flash[:error] = "App unsuspension has failed. Please try again."
    end

    redirect_to stafftools_business_app_path(id: integration.slug)
  end

  def suspend_all # rubocop:todo GitHub/UseRestfulActions
    if Integration.suspend_all_for_owner(actor: current_user, owner: this_business, reason: params[:reason])
      flash[:notice] = "All integrations owned by #{this_business.slug} have been suspended."
    else
      flash[:error] = "App suspension has failed. Please try again."
    end
    redirect_to stafftools_business_apps_path(business_id: this_business.slug)
  end

  def unsuspend_all # rubocop:todo GitHub/UseRestfulActions
    if Integration.unsuspend_all_for_owner(actor: current_user, owner: this_business)
      flash[:notice] = "All integrations owned by #{this_business.slug} have been unsuspended."
    else
      flash[:error] = "App unsuspension has failed. Please try again."
    end
    redirect_to stafftools_business_apps_path(business_id: this_business.slug)
  end

  private

  def show_view
    @show_view = Stafftools::Integrations::ShowView.new \
      integration: integration,
      hook_deliveries_query: params[:deliveries_q],
      query: params[:query]
  end

  def integration # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @integration ||= this_business.integrations.find_by_slug!(params[:id])
  end
end
