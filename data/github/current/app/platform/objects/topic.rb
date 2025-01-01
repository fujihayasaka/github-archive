# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Topic < Platform::Objects::Base
      description "A topic aggregates entities that are related to a subject."

      implements_node templates: [[:t, :topic_name]], as: "TO", ready_date: Platform::Helpers::GlobalId::COHORT_4, uses_database_id: false do |topic|
        {
          prefix: :t,
          topic_name: topic.name
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, topic)
        permission.access_allowed?(:public_site_information, resource: Platform::PublicResource.new, current_repo: nil, current_org: nil, allow_integrations: true, allow_user_via_granular_actor: true) # rubocop:disable GitHub/PublicResource
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # topics are public
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      implements Interfaces::Starrable
      database_id_field(visibility: :internal)

      field :name, String, "The topic's name.", null: false
      field :is_flagged, Boolean, "Whether the topic has been flagged as objectionable.", visibility: :internal, method: :flagged, null: false
      field :is_featured, Boolean, "Whether this topic is featured on GitHub.", mobile_only: true, method: :featured?, null: false
      field :is_curated, Boolean, "Whether this topic has additional curated content, such as a short description.", mobile_only: true, method: :curated?, null: false
      field :short_description, String, "Returns a short description of this topic.", mobile_only: true, null: true
      field :description, String, "Returns a description of this topic.", mobile_only: true, null: true
      field :created_at, Scalars::DateTime, "When the topic record was created on GitHub.", visibility: :under_development, null: true
      field :created_by, String, "The person, people, or group that created the subject this topic is about.", visibility: :internal, null: true
      field :released, String, "When the subject of this topic was first released or created.", visibility: :internal, null: true
      field :external_url, Scalars::URI, "A link to a website about this topic.", mobile_only: true, null: true
      field :wikipedia_url, Scalars::URI, "A link to a Wikipedia page about this topic.", mobile_only: true, null: true
      field :logo_url, Scalars::URI, "Returns the URL for an image representing this topic.", mobile_only: true, null: true
      field :github_url, Scalars::URI, "A link to a GitHub repository or organization for this topic.", mobile_only: true, null: true
      field :is_github_url_a_repository, Boolean, "Returns true if the GitHub URL is to a repository.", method: :github_url_is_repository?, visibility: :internal, null: true
      field :alias_source_topic, Objects::Topic, "The topic that has this topic as an alias, if any.", visibility: :internal, null: true

      field :latest_release, Objects::Release, "Returns the latest release for this topic.", visibility: :internal, null: true

      def latest_release
        @object.latest_release(@context[:viewer])
      end

      field :repositories, resolver: Resolvers::Repositories, description: "A list of repositories.", connection: true do
        argument :sponsorable_only, Boolean,
          required: false,
          description: "If true, only repositories whose owner can be sponsored via GitHub Sponsors will be returned.",
          visibility: { public: { environments: [:dotcom] }, internal: { environments: [:enterprise] } },
          default_value: false
      end

      field :display_name, String, mobile_only: true, method: :safe_display_name, description: <<~DESCRIPTION, null: false do
          Returns the properly capitalized display name of this topic if one is known, otherwise
          returns the topic's name.
        DESCRIPTION
      end

      def external_url
        @object.url
      end

      field :formatted_days_since_latest_release, String, visibility: :internal, description: <<~DESCRIPTION, null: true do
          Returns a string describing the amount of time that has elapsed since the relevant
          repository's latest release.
        DESCRIPTION
      end

      def formatted_days_since_latest_release
        @object.formatted_days_since(@object.latest_release(@context[:viewer]))
      end

      field :description_html, Scalars::HTML, mobile_only: true, description: "The description of the topic rendered to HTML.", null: false

      def description_html
        GitHub.cache.fetch("@object:#{@object}:#{@object.updated_at.to_i}:description") do
          GitHub::Goomba::TopicDescriptionPipeline.to_html(@object.description, {})
        end
      end

      url_fields description: "The HTTP URL for this topic.", mobile_only: true do |topic, _arguments, _context|
        topic.resource_path
      end

      field :stafftools_info, Objects::TopicStafftoolsInfo, description: "Fields that are only visible to site admins.", null: true

      def stafftools_info
        if self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          Models::TopicStafftoolsInfo.new(@object)
        else
          nil
        end
      end

      field :related_topics, [Objects::Topic], description: <<~DESCRIPTION, null: false do
          A list of related topics, including aliases of this topic, sorted with the most relevant
          first. Returns up to 10 Topics.
        DESCRIPTION
        argument :first, Integer, "How many topics to return.", default_value: 3, required: false
      end

      def related_topics(first:)
        # If `first` isn't specified, use the default value.
        # See https://github.com/github/communities/issues/1105.
        first = first || Topic.fields["relatedTopics"].arguments["first"].default_value

        if first > 10
          raise Platform::Errors::ArgumentLimit, "up to 10 topics is supported"
        else
          related_topics = ::Topic.applied_and_related_to(@object.name, limit: first)
          ArrayWrapper.new(related_topics)
        end
      end

      def self.load_from_global_id(name)
        Loaders::ActiveRecord.load(::Topic, name, column: :name).then do |topic|
          # Topics are uniquely defined by their name. We even want to return
          # `Topic` objects for valid names that have not been stored in the
          # database yet.
          unless topic
            new_topic = ::Topic.new(name: name)
            topic = new_topic if new_topic.valid?
          end

          topic
        end
      end
    end
  end
end
