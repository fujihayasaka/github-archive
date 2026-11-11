# typed: strict
# frozen_string_literal: true

class Stafftools::CopilotModelRegistryController < StafftoolsController

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:index]

  before_action :dotcom_required

  sig { void }
  def index
    registry_models = pull_models
    cached = Copilot::ModelsRegistryCache.all.to_a
    models_diff = Copilot::ModelsRegistryCache.models_changed?(cached, registry_models)
    render "stafftools/copilot_model_registry/index", locals: {
      cached_models: cached,
      registry_models: registry_models,
      models_diff: models_diff,
    }
  end

  sig { void }
  def create
    begin
      Copilot::ModelsRegistryCache.save_models
    rescue StandardError => e
      redirect_to stafftools_copilot_model_registry_index_path, alert: "Failed to refresh model registry cache: #{e.message}" and return
    end
    redirect_to stafftools_copilot_model_registry_index_path, notice: "Model registry cache refreshed"
  end

  sig { void }
  def destroy
    begin
      Copilot::ModelsRegistryCache.clear_models
    rescue StandardError => e
      redirect_to stafftools_copilot_model_registry_index_path, alert: "Failed to clear models: #{e.message}" and return
    end
    redirect_to stafftools_copilot_model_registry_index_path, notice: "Model registry cache cleared"
  end

  private

  # rubocop:disable GitHub/UseRestfulActions
  sig { returns(T::Array[Copilot::ModelsRegistryCache]) }
  def pull_models
    Copilot::ModelsRegistryCache.pull_models
  end

end
