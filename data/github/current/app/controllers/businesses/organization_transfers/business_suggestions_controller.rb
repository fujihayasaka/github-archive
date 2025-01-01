# typed: true
# frozen_string_literal: true

class Businesses::OrganizationTransfers::BusinessSuggestionsController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    respond_to do |format|
      format.html do
        render Businesses::OrganizationTransfers::PossibleBusinessesComponent.new(
          from_business: this_business,
          viewer: current_user,
          query: params[:query]
        ), layout: false
      end

      format.html_fragment do
        render Businesses::OrganizationTransfers::PossibleBusinessesComponent.new(
          from_business: this_business,
          viewer: current_user,
          query: params[:query]
        ), layout: false
      end
    end
  end
end
