# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::OrganizationSuggestionsController < Stafftools::Businesses::BusinessBaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:index]

  def index
    organizations = ::Organization.search(params[:q], limit: 10)
    respond_to do |format|
      format.html_fragment do
        render partial: "stafftools/businesses/organization_suggestions", formats: :html, locals: {
          organizations: organizations, business: this_business
        }
      end
    end
  end
end
