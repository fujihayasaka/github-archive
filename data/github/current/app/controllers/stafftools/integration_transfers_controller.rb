# typed: true
# frozen_string_literal: true

class Stafftools::IntegrationTransfersController < StafftoolsController
  before_action :ensure_user_exists
  before_action :ensure_target_exists, only: [:create]
  before_action :check_valid_target, only: [:create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:transfer_suggestions]

  def create
    transfer_result = Integration::Transfers::Service.stafftools_transfer_ownership(
      integration: integration,
      target: transfer_target,
      staff_user: current_user,
      entry_point: :stafftools
    )

    if transfer_result.success?
      flash[:notice] = "Transferred ownership of #{integration.slug} to #{transfer_target.display_login}."
    else
      flash[:error] = "Failed to transfer ownership of #{integration.slug} to #{transfer_target.display_login}."
    end

    redirect_to gh_stafftools_app_path(integration.owner, integration)
  end

  def transfer_suggestions # rubocop:todo GitHub/UseRestfulActions
    visible_suggestions = cap_filter
      .authorized_resources(suggestions_view_model.suggestions)
      .reject { |transfer_suggestion| transfer_suggestion == integration_owner }

    render Apps::Transfers::TargetAutocompleteComponent.new(
      suggestions: visible_suggestions
    )
  end

  private

  def ensure_target_exists
    unless transfer_target
      flash[:error] = "Transfer target #{params[:transfer_to]} not found."

      redirect_to gh_stafftools_app_path(integration.owner, integration)
    end
  end

  def check_valid_target
    if !integration.valid_target?(transfer_target)
      flash[:error] = "This integration cannot be transferred to #{transfer_target.display_login} because #{transfer_target.display_login} does not belong to the App Owner's Enterprise."

      redirect_to gh_stafftools_app_path(integration.owner, integration)
    end
  end

  def suggestions_view_model
    business = integration.owner_enterprise_managed_business

    create_view_model(AutocompleteView,
      query: params[:q],
      with_orgs: true,
      with_businesses: suggest_businesses?,
      exclude_suspended: true,
      business: business
    )
  end

  def suggest_businesses?
    return false if integration.public_visibility? && !owner_is_enterprise_managed?

    true
  end

  def owner_is_enterprise_managed?
    case integration_owner
    when Organization
      integration_owner.enterprise_managed_user_enabled?
    when User
      integration_owner.is_enterprise_managed?
    else
      false
    end
  end

  memoize def transfer_target
    Integration::Transfers::Query.find_target_by_params(transfer_to: params[:transfer_to])
  end

  memoize def integration
    this_user.integrations.find_by_slug!(params[:app_id])
  end

  memoize def integration_owner
    integration.owner
  end
end
