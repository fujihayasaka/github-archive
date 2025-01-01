# typed: true
# frozen_string_literal: true

class Orgs::TopLanguagesController < Orgs::Controller
  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    only: [:index]

  def index
    respond_to do |format|
      format.html do
        render partial: "orgs/top_languages", locals: {
          view: create_view_model(Orgs::Repositories::IndexPageView,
            organization: this_organization,
            current_page: current_page,
            type_filter: params[:type],
            phrase: params[:q],
            language: params[:language],
            context: params[:context],
          ),
        }
      end
    end
  end
end
