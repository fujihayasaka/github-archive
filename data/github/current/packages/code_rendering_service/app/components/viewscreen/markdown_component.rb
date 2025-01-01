# typed: true
# frozen_string_literal: true

module Viewscreen
  class MarkdownComponent < ApplicationComponent
    include CodeRenderingService::QueryParams
    attr_reader :render_type, :view_type, :entity, :opts

    # FIXME: doing this at load time forces autoloading of all referenced models
    VALID_ENTITIES = [Repository, Organization, Team, Gist, CheckSuite, ::GitHub::Unsullied::Page, ::GitHub::Unsullied::Wiki, MemexProject].freeze
    SUPPORTED_VIEWS = {
      mermaid: [:markdown],
      geojson: [:markdown],
      topojson: [:markdown],
      stl: [:markdown],
    }.freeze
    FLAGGED_FEATURES = [].freeze

    def self.selector_list
      SUPPORTED_VIEWS.keys.map do |render_type|
        "pre[lang='#{render_type}']"
      end.join(",")
    end

    def self.org_access?(flag, entity)
      return false unless entity.respond_to?(:organization) && entity.respond_to?(:organization_id)

      entity.async_organization.then do |_organization|
        # Gists respond to organization, but always return nil
        return false if entity.organization.nil?
        FeatureFlag.vexi.enabled?(flag, entity.organization, default: false)
      end.sync
    end

    def self.repo_access?(flag, entity)
      return false unless entity.respond_to?(:repository) && entity.respond_to?(:repository_id)

      entity.async_repository.then do |_repository|
        return false if entity.repository.nil?
        FeatureFlag.vexi.enabled?(flag, entity.repository, default: false)
      end.sync
    end

    def self.owner_access?(flag, entity)
      return false unless entity.respond_to?(:owner) && entity.owner&.respond_to?(:vexi_id)

      FeatureFlag.vexi.enabled?(flag, entity.owner, default: false) || self.org_access?(flag, entity.owner) || self.repo_access?(flag, entity.owner)
    end

    # An entity is valid if it is an approved team, org, or repo, or if the owner of a repository or team
    # is an approved organization, if it's a gist or if it responds to an approved repository.
    # RenderTypes that aren't explicitly in the list of flagged types are assumed
    # to be enabled.
    def self.enabled_for_entity?(render_type, entity)
      return false unless VALID_ENTITIES.any? { |type| entity.is_a?(type) }
      return true if !FLAGGED_FEATURES.include?(render_type)

      flag = "markdown-#{render_type}".to_sym

      if entity.respond_to?(:vexi_id)
        return true if FeatureFlag.vexi.enabled?(flag, entity, default: false)
      end

      self.org_access?(flag, entity) || self.repo_access?(flag, entity) || self.owner_access?(flag, entity)
    end

    def self.supported_views_for_entity(entity)
      SUPPORTED_VIEWS.keys.select do |render_type|
        self.enabled_for_entity?(render_type, entity)
      end
    end

    def initialize(render_type: :mermaid, view_data: nil, entity: nil, opts: {})
      @render_type = render_type
      @view_type = :markdown
      @view_data = view_data
      @entity = entity
      @html_safe = opts.delete(:html_safe)
      @opts = opts
    end

    def host_url
      Viewscreen.host_url
    end

    def flagged_features
      FLAGGED_FEATURES
    end

    def supports_view?
      supported_views.keys.include?(render_type) &&
      supported_views[render_type].include?(@view_type) && self.class.enabled_for_entity?(render_type, entity)
    end

    memoize def identity
      SecureRandom.uuid
    end

    def iframe_url
      query = {
        docs_host: GitHub.help_url
      }

      URI.parse([
        host_url,
        "markdown",
        "#{render_type}?#{query.to_param}"
      ].compact.join("/"))
    end

    memoize def view_data
      data = @view_data.gsub(/"/, "&quot;")
      return data unless @html_safe
      data.html_safe # rubocop:disable Rails/OutputSafety
    end

    def viewdata_as_json
      {
        data: @view_data,
      }.to_json
    end

    private

    def supported_views
      SUPPORTED_VIEWS
    end
  end
end
