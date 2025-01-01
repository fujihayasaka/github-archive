# typed: true
# frozen_string_literal: true

class NewTopicImporter
  EXPLORE_FEED_URL = "https://explore-feed.github.com".freeze

  attr_reader :errors

  def initialize
    @changesets = []
    @errors = []
    @topics = {}
  end

  def import(dry_run: false, topic_names: [])
    topics_to_update = raw_topics

    unless dry_run
      topics_to_update = topics_to_update.select { |topic_data| topic_names.include?(topic_data.with_indifferent_access[:topic_name]) }
    end

    measure(metric: "import_topic_from_directory_overall", dry_run:) do
      topics_to_update.each do |topic_data|
        measure(metric: "import_topic_from_directory", dry_run:) do
          import_topic(topic_data.with_indifferent_access, dry_run:)
        end
      end
    end

    remove_curated_content(dry_run:)
  end

  def new_count
    new_topic_changesets.size
  end

  def any_new?
    new_count > 0
  end

  def any_updates?
    updated_count > 0
  end

  def any_changes?
    any_new? || any_updates?
  end

  def updated_topic_changesets
    @changesets.select(&:changed?)
  end

  def new_topic_changesets
    @changesets.select(&:new?)
  end

  def updated_count
    updated_topic_changesets.size
  end

  private

  def remove_curated_content(dry_run:)
    all_curated_topic_names = measure(metric: "all_curated_topic_names") do
      Topic.curated.pluck(:name)
    end

    topic_names_to_decurate = all_curated_topic_names - raw_topics.map { |topic_data| topic_data.with_indifferent_access[:topic_name] }
    return if topic_names_to_decurate.empty?

    measure(metric: "remove_curated_content_from_overall", dry_run:) do
      topic_names_to_decurate.each_slice(100) do |names_batch|
        remove_curated_content_from(names_batch, dry_run:)
      end
    end
  end

  def remove_curated_content_from(topic_names, dry_run:)
    topics = Topic.where(name: topic_names)

    if dry_run
      measure(metric: "remove_curated_content_from", dry_run: true) do
        topics.each do |topic|
          changeset = TopicChangeset.new(topic)
          topic.attributes.merge!(nilled_fields.merge(featured: false))

          measure(metric: "changeset_determine_changes", dry_run: true) do
            changeset.determine_changes
          end

          @changesets << changeset
        end
      end
    else
      measure(metric: "remove_curated_content_from", dry_run: false) do
        topics.update_all(nilled_fields.merge(featured: false))
      end
    end
  end

  def import_topic(topic_data, dry_run:)
    topic_name = topic_data[:topic_name]

    topic = Topic.find_by_name(topic_name) || Topic.new(name: topic_name)
    changeset = TopicChangeset.new(topic)

    new_aliases = Array.wrap(topic_data[:aliases]).join(Topic::ALIAS_DELIMITER) || ""
    new_related = Array.wrap(topic_data[:related]).join(Topic::RELATED_DELIMITER) || ""

    topic.description = encode_value_if_present(topic_data[:content])
    topic.created_by = encode_value_if_present(topic_data[:created_by])
    topic.display_name = encode_value_if_present(topic_data[:display_name])
    topic.logo_url = logo_url_from(topic_data)
    topic.released = encode_value_if_present(topic_data[:released])
    topic.short_description = encode_value_if_present(topic_data[:short_description])
    topic.url = topic_data[:url]
    topic.wikipedia_url = topic_data[:wikipedia_url]
    topic.github_url = topic_data[:github_url]

    changeset.determine_changes(topic_data)
    anything_to_save = changeset.new? || changeset.changed?
    @changesets << changeset if anything_to_save

    if anything_to_save && !dry_run
      unless topic.save
        @errors.concat topic.errors.full_messages
      end

      topic.update_aliases_from_names(new_aliases)
      topic.update_related_topics_from_names(new_related)
    end

    @topics[topic_name] = topic
  end

  def logo_url_from(topic_data)
    return unless topic_data[:logo]

    topic_data[:logo]
  end

  def nilled_fields
    Topic::CURATED_FIELDS.map { |field| [field, nil] }.to_h
  end

  def raw_topics
    GitHub::JSON::CachedFetchRemoteUrl.fetch(
      url: "#{EXPLORE_FEED_URL}/feed.json",
      cache_key: "explore:topics:latest",
      default_value: [],
      hash_subkey: "topics",
    )
  end

  def encode_value_if_present(value)
    return unless value.present?

    value = value.to_s

    if value.respond_to?(:force_encoding) && value.encoding != ::Encoding::UTF_8
      value.force_encoding("UTF-8")
    end

    value
  end

  def measure(metric:, dry_run: false)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    result = yield

    GitHub.dogstats.distribution(
      "biztools.topics.import.dist.time",
      GitHub::Dogstats.duration(start),
      tags: ["#{dry_run ? 'dry_run' : 'real'}:#{metric}"],
    )

    result
  end
end
