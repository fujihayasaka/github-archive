# typed: strict
# frozen_string_literal: true

module ContextRegion
  class Factory
    VALID_CRUMB_TYPE_PARAMS = %i[
      business
      user
      repository
      organization
      team
  ].freeze

    sig { returns(T::Hash[Symbol, ContextRegion::Crumb]) }
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

    sig { params(crumb_type: Symbol).returns(T::Boolean) }
    def self.valid_crumb_type?(crumb_type)
      VALID_CRUMB_TYPE_PARAMS.include?(crumb_type)
    end

    sig { params(crumb_type: Symbol, crumb_object_identifier: String, current_user: User).returns(T.nilable(ContextRegion::Crumb)) }
    def self.build_from_query_params(crumb_type:, crumb_object_identifier:, current_user:)
      return nil unless valid_crumb_type?(crumb_type)

      crumb_object = case crumb_type
      when :business
        object = Business.find_by(slug: crumb_object_identifier)
        object&.member?(current_user) ? object : nil
      when :user
        User.find_by(login: crumb_object_identifier)
      when :organization
        object = Organization.find_by(login: crumb_object_identifier)
        object&.readable_by?(current_user) ? object : nil
      when :repository
        object = Repository.with_name_with_owner(crumb_object_identifier)
        object&.public? || object&.readable_by?(current_user) ? object : nil
      when :team
        object = Team.find_by_combined_slug(crumb_object_identifier)
        object&.visible_to?(current_user) ? object : nil
      else
        nil
      end

      return nil unless crumb_object

      build(crumb_object, current_user: current_user)
    end

    sig { params(object: T.anything, options: T.untyped).returns(T.nilable(ContextRegion::Crumb)) }
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

    sig { params(preset_name: Symbol).returns(T.nilable(ContextRegion::Crumb)) }
    def self.preset(preset_name)
      presets[preset_name]
    end
  end
end
