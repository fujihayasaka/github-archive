# typed: true
# frozen_string_literal: true

class Businesses::SupportEntitleeSuggestionsController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: %i(index)

  def index
    respond_to do |f|
      f.html_fragment do
        render partial: "businesses/settings/support_suggestions",
          formats: :html,
          locals: {
            view: create_view_model(Businesses::Settings::SupportSuggestionsView,
              business: this_business,
              query: params[:q]
            )
          }
      end
    end
  end
end
