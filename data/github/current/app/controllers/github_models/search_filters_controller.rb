# typed: true
# frozen_string_literal: true

class GitHubModels::SearchFiltersController < ApplicationController
  before_action :github_models_required

  depends_on_clusters ApplicationRecord::GitHubModels,
    ApplicationRecord::Mysql1, only: [:index]

  def index
    return head(:not_acceptable) unless request.xhr?
    publishers = GitHubModels::Publisher.publicly_visible.sort_by { |publisher| publisher.display_name.downcase }
      # We don't actually need model counts for rendering search filters, so avoid extra DB queries:
      .map { |publisher| publisher.to_h(total_models: -1) }
    payload = T.let({
      categories: GitHubModels::Model.publicly_visible_tags,
      publishers: publishers,
    }, GitHubModels::Types::SearchFiltersPayload)
    render json: payload.to_json
  end

  private

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end
end
