# typed: true
# frozen_string_literal: true
module Search
  class RepositoryActionResultView
    include UrlHelpers
    include Search::RepositoryActionIconHelper
    include Scientist

    attr_reader :id, :name, :description, :created, :updated, :repository_action,
      :primary_category, :secondary_category, :categories, :slug, :type, :stars, :owner_login, :is_verified_owner,
      :model_name, :resource_path, :dependents_count
    alias :owner_display_login :owner_login

    # Create a new RepositoryActionResultView from a `repository_action` document hash
    # returned from the ElasticSearch index.
    #
    # hash - Document Hash returned by ElasticSearch
    #
    def initialize(hash)
      source = hash["_source"]
      @id = hash["_id"]
      @repository_action = hash["_model"]
      @name = source["name"]
      @description = source["description"]
      @highlights = hash["highlight"]
      @primary_category = source["primary_category"]
      @secondary_category = source["secondary_category"]
      @categories = source["categories"]
      @slug = @repository_action.slug
      @type = tool_type
      @stars = source["stars"]
      @owner_login = source["owner_login"]
      @is_verified_owner = source["is_verified_owner"]
      @model_name = RepositoryAction.to_s
      @resource_path = marketplace_action_path(slug: @repository_action.slug)
      @dependents_count = source["dependents_count"]
    end

    def tool_type
      "repository_action"
    end

    # Returns true if there are highlight fragments for this action. The
    # highlight fragments contain text from the various action fields with the
    # relevant search terms surrounded by <em> tags.
    def highlights?
      !@highlights.nil?
    end

    # Return the action name. The name may or may not contain
    # highlight tags, but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped name String.
    def hl_name
      @hl_name ||= hl_description("name.ngram", @name)
    end

    # Return the action short_description. The short_description may or may not contain
    # highlight tags, but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped short_description String.
    def hl_short_description
      @hl_description ||= hl_description("short_description", @description)
    end

    def populate_results_data
      @icon_svg = svg_icon_string(@repository_action.icon_name, owner: @owner_login)
    end

    def for_frontend_rendering
      populate_results_data
      {
        # From BaseMarketplaceResult
        type: @type,
        id: @id,
        name: @name,
        free: @free,
        primary_category: @primary_category,
        secondary_category: @secondary_category,
        is_verified_owner: @is_verified_owner,
        slug: @slug,
        owner_login: @owner_login,
        resource_path: @resource_path,
        highlights: {
          description: @highlights.nil? ? "" : @highlights[:description],
          'name.ngram': @highlights.nil? ? "" : @highlights["name.ngram"],
        },

        # From RepositoryActionResult
        description: @description,
        stars: @stars,
        dependents_count: @dependents_count,
        icon_svg: @icon_svg,
        repository_action: {
          repository_action: {
            id: @repository_action[:id],
            path: @repository_action[:path],
            name: @repository_action[:name],
            description: @repository_action[:description],
            icon_name: @repository_action[:icon_name],
            color: @repository_action.color,
            featured: @repository_action[:featured],
            repository_id: @repository_action[:repository_id],
            rank_multiplier: @repository_action[:rank_multiplier],
            slug: @repository_action[:slug],
          },
        }
      }
    end

    private

    def hl_description(key, value)
      if highlights? && @highlights.key?(key)
        GitHub::Goomba::HighlightedSearchResultPipeline.to_html(@highlights[key].first)
      else
        formatted = GitHub::Goomba::DescriptionPipeline.to_html(value.to_s)
        HTMLTruncator.new(formatted, 350).to_html(wrap: false)
      end
    end
  end
end
