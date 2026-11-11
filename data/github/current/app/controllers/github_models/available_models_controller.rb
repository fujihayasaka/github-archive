# typed: true
# frozen_string_literal: true

class GitHubModels::AvailableModelsController < ApplicationController
  before_action :login_required
  before_action :github_models_required

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::Mysql1

  def index
    available_models = models_user.models(sort: :publisher)
    rate_limit_tier = params[:rate_limit_tier]
    publisher = params[:publisher]

    if rate_limit_tier.present?
      available_models_at_tier = available_models.select { |model| model.rate_limit_tier == rate_limit_tier }
      sorted_models = if publisher.present?
        priority_models, other_models = available_models_at_tier.partition { |m| m.publisher == publisher }
        priority_models.concat(other_models)
      else
        available_models_at_tier
      end
      return render json: sorted_models.first(3).map(&:to_featured_model).to_json
    end

    render json: available_models.map { |model| models_user.model_hash(model) }.to_json
  end

  private

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  sig { returns(GitHubModels::User) }
  memoize def models_user
    GitHubModels::User.new(user: current_user)
  end
end
