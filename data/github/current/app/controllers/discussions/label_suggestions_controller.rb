# typed: true
# frozen_string_literal: true

class Discussions::LabelSuggestionsController < Discussions::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    only: [:index]

  def index
    label_suggestions = Discussion.label_name_suggestions_for(current_repository).map do |label_name|
      { value: label_name }
    end

    respond_to do |format|
      format.json do
        render json: label_suggestions
      end
    end
  end
end
