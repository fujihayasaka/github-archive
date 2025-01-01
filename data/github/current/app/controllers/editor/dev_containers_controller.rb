# typed: true
# frozen_string_literal: true

module Editor
  class DevContainersController < ApplicationController

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Repositories

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index], optional: true

    helper_method  :search_placeholder

    layout false

    def index
      return render_404 if !request.xhr?

      render "editor/dev_containers/index", formats: :html, locals: {
        suggested_features: suggested_features
      }
    end

    def show
      feature = Codespaces::DevContainers::dev_container_feature_from_id(feature_id: params[:feature_id])
      if feature.nil?
        render_404
      else
        render "editor/dev_containers/show", locals: { feature: feature }
      end
    end

    private

    def target_for_conditional_access
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end

    def suggested_features
      Codespaces::DevContainers::dev_container_collection_metadata_for_features
    end

    def search_placeholder(category: nil)
      if category.present?
        "Search for #{category.capitalize} Features"
      else
        "Search for Features"
      end
    end
  end
end
