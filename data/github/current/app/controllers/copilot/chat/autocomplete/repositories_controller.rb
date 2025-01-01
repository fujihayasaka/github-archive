# typed: true
# frozen_string_literal: true

class Copilot::Chat::Autocomplete::RepositoriesController < Copilot::Chat::AutocompleteController
  include Suggestions::RepositoriesDependency

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories

  RESULT_LIMIT = 5

  def index
    respond_to do |format|
      format.json do
        render json: repositories_payload(query: query_value, limit: RESULT_LIMIT)
      end
    end
  end

  private

  def query_value
    params[:q].to_s.strip.downcase || ""
  end

  def resource_for_conditional_access
    self
  end

  def target_for_conditional_access
    current_user
  end
end
