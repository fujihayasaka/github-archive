# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::AdminSuggestionsController < Stafftools::Businesses::BusinessBaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    only: [:index]

  def index
    headers["Cache-Control"] = "no-cache, no-store"
    view = create_view_model \
      ::Businesses::Admins::SuggestionsView,
      business: this_business,
      stafftools_invite: true,
      query: params[:q],
      exclude_suspended: true

    respond_to do |format|
      format.html_fragment do
        render partial: "businesses/admins/suggestions", formats: :html, locals: { view: view }
      end
      format.html do
        render partial: "businesses/admins/suggestions", locals: { view: view }
      end
    end
  end
end
