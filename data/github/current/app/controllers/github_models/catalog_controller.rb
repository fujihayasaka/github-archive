# typed: true
# frozen_string_literal: true

class GitHubModels::CatalogController < ApplicationController
  include GitHubModels::RenderDependency

  before_action :github_models_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam

  def index
    render json: gateway_catalog_models.to_json
  end

  private

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def gateway_catalog_models
    GitHubModels.domain.models.find_many(publicly_visible_only: true).map do |model|
      {
        id: model.downcased_external_slug,
        name: model.friendly_name,
        publisher: model.publisher,
        summary: model.summary,
        rate_limit_tier: model.rate_limit_tier,
        supported_input_modalities: model.supported_input_modalities,
        supported_output_modalities: model.supported_output_modalities,
        tags: model.tags
      }
    end
  end
end
