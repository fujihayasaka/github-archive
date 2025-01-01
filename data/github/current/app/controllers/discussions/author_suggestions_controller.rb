# typed: true
# frozen_string_literal: true

class Discussions::AuthorSuggestionsController < Discussions::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:index]

  def index
    author_logins = Discussion.author_login_suggestions_for(current_repository, viewer: current_user)
    author_suggestions = author_logins.map { |login| { value: login } }

    respond_to do |format|
      format.json do
        render json: author_suggestions
      end
    end
  end
end
