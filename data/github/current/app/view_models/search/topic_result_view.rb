# typed: true
# frozen_string_literal: true

module Search
  class TopicResultView
    MAX_VISIBLE_RELATED_TOPICS = 3

    attr_reader :id, :short_description, :name, :topic, :starred_by_current_user

    # Create a new TopicResultView from a `page` document hash returned from
    # the Elasticsearch index.
    #
    # hash - Document Hash returned by Elasticsearch
    def initialize(hash)
      source = hash["_source"]
      @id = hash["_id"]
      @topic = hash["_model"]
      @name = source["name"]
      @display_name = source["display_name"]
      @short_description = source["short_description"]
      @description = source["description"]
      @created_by = source["created_by"]
      @released = source["released"]
      @featured = source["featured"]
      @curated = source["curated"]
      @aliases = source["aliases"]
      @related = source["related"]
      @repository_count = source["repository_count"]
      @created_at = Time.parse(source["created_at"])
      @updated_at = Time.parse(source["updated_at"])
      @highlights = hash["highlight"]
    end

    def any_related_topics?
      related_topic_names.any?
    end

    def related_topic_names
      @related_topic_names ||= (@aliases | @related).uniq
    end

    def visible_related_topic_names
      @visible_related_topic_names ||= related_topic_names[0...MAX_VISIBLE_RELATED_TOPICS]
    end

    def hidden_related_topic_names
      @hidden_related_topic_names ||=
        related_topic_names[MAX_VISIBLE_RELATED_TOPICS...related_topic_names.length]
    end

    def hidden_related_topic_count
      if hidden_related_topic_names
        hidden_related_topic_names.size
      else
        0
      end
    end

    def include_comma?(index)
      index < visible_related_topic_names.length - 1 || hidden_related_topic_count > 0
    end

    def display_name
      @display_name.presence || name
    end

    def has_logo?
      logo_url.present?
    end

    def logo_url
      @topic.logo_url
    end

    def curated?
      @curated
    end

    def topic_url(topic_name)
      if GitHub.enterprise? # no topic pages on Enterprise, only search
        template_args = { name: topic_name }
        template = "/search?q=topic%3A{name}&type=Repositories"
        addressable = Addressable::Template.new(template).expand(template_args)
        addressable.to_s
      else # link to topic page on dotcom
        "/topics/#{topic_name}"
      end
    end

    def url
      topic_url(name)
    end

    # Returns true if there are highlight fragments for this topic. The
    # highlight fragments contain text from the various topic fields with the
    # relevant search terms surrounded by <em> tags.
    def highlights?
      !@highlights.nil?
    end

    def hl_short_description
      return @hl_short_description if defined? @hl_short_description

      @hl_short_description = if highlights? && @highlights.key?("short_description")
        @highlights["short_description"].first
      else
        ERB::Util.force_escape(short_description)
      end
    end

    # Return the topic display name. The display name may or may not contain highlight tags,
    # but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped display name String.
    def hl_display_name
      return @hl_display_name if defined? @hl_display_name

      highlight_key = display_name ? "display_name" : "name.ngram"
      default_text = display_name || name

      @hl_display_name = if highlights? && @highlights.key?(highlight_key)
        @highlights[highlight_key].first
      else
        ERB::Util.force_escape(default_text)
      end
    end

    def repository_count_over_max_fetch_limit?
      @repository_count && @topic && @repository_count > @topic.public_repo_count_max
    end

    def repository_count
      if repository_count_over_max_fetch_limit?
        @repository_count.floor(-Math.log10(@topic.public_repo_count_max))
      else
        @repository_count
      end
    end

    def populate_results_data(starred_by_current_user)
      @starred_by_current_user = starred_by_current_user

      hl_short_description if short_description

      hl_display_name
    end

    def for_frontend_rendering
      {
        id: @id,
        name: @topic.name,
        flagged: @topic.flagged,
        short_description: @topic.short_description,
        display_name: @topic.display_name,
        released: @topic.released,
        wikipedia_url: @topic.wikipedia_url,
        url: @topic.url,
        github_url: @topic.github_url,
        logo_url: @topic.logo_url,
        has_logo_url: @topic.has_logo_url,
        featured: @topic.featured,
        stargazer_count: @topic.stargazer_count,
        applied_count: @topic.applied_count,
        hl_display_name: @hl_display_name,
        hl_short_description: @hl_short_description,
        created_by: @created_by,
        curated: @curated,
        aliases: @aliases,
        related: @related,
        repository_count: repository_count,
        repository_count_over_max_fetch_limit: repository_count_over_max_fetch_limit?,
        starred_by_current_user: @starred_by_current_user,
        highlights: {
          description: @highlights&.fetch(:description, nil),
          display_name: @highlights&.fetch(:display_name, nil),
          'name.ngram': @highlights&.fetch("name.ngram", nil)
        }
      }
    end

    def self.from_model(topic)
      source = {
        "created_at" => topic.created_at.iso8601,
        "updated_at" => topic.updated_at.iso8601,
        "display_name" => topic.display_name,
        "name" => topic.name,
        "created_by" => topic.created_by,
        "description" => topic.description,
        "short_description" => topic.short_description,
        "released" => topic.released,
        "featured" => topic.featured?,
        "curated" => topic.curated?,
        "aliases" => topic.alias_names,
        "related" => topic.related_topic_names,
      }
      new("_id" => topic.id.to_s, "_source" => source, "_model" => topic)
    end
  end
end
