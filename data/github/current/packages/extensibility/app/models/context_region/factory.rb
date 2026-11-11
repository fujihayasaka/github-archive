# typed: true
# frozen_string_literal: true

module ContextRegion
  class Factory
    def self.presets
      {
        copilot: BasicCrumb.new(nil, label: "Copilot", path_name: :copilot_immersive_path),
        codespaces: BasicCrumb.new(nil, label: "Codespaces", path_name: :codespaces_path),
        developer_settings: DeveloperSettingsCrumb.new,
        explore: ExploreCrumb.new,
        topics: BasicCrumb.new(nil, label: "Topics", path_name: :topics_path),
        trending: BasicCrumb.new(nil, label: "Trending", path_name: :trending_index_path),
        notifications: BasicCrumb.new(nil, label: "Notifications", path_name: :notifications_v2_index_path),
        settings: BasicCrumb.new(nil, label: "Settings", path_name: :settings_path),
        stafftools: BasicCrumb.new(nil, label: "Site admin", path_name: :stafftools_path),
        marketplace: MarketplaceCrumb.new,
        marketplace_apps: Marketplace::AppsCrumb.new,
        marketplace_actions: Marketplace::ActionsCrumb.new,
        marketplace_models: Marketplace::ModelsCrumb.new,
        mcp: McpCrumb.new,
        models: BasicCrumb.new(nil, label: "Models", path_name: :models_path),
        spark: BasicCrumb.new(nil, label: "Spark", path_name: :spark_dashboard_path),
      }
    end

    def self.build(object, **options)
      case object
      when Business
        BusinessCrumb.new(object, **options)
      when Repository
        RepositoryCrumb.new(object, **options)
      when User, Organization
        UserCrumb.new(object, **options)
      when MemexProject
        MemexCrumb.new(object, **options)
      when Team
        TeamCrumb.new(object, **options)
      else
        nil
      end
    end

    def self.preset(preset_name)
      presets[preset_name]
    end
  end
end
