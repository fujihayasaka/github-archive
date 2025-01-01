# typed: false
# frozen_string_literal: true

class TopicImporter
  TOPICS_PATH = "topics"
  REPO_NWO = "github/explore"
  INDEX_FILE_NAME = "index.md"

  attr_reader :errors, :topics_repository

  def initialize(topics_repository:)
    @topics_repository = topics_repository
    @errors = []
    @topics = {}
    @changesets = []
  end

  # Public: Create and update Topic records from the latest data in the github/explore repo. Any
  # topic that is no longer in github/explore will have its curated content wiped.
  #
  # dry_run - set to true if no writes should be made; useful for previewing changes
  # topic_names - a list of String topic names that should be updated; ignored when dry_run is true;
  #               only used to determine setting curated content, not wiping it
  #
  # Returns nothing.
  def import(dry_run:, topic_names: [])
    if topics_repository.nil? || topics_repository.destroyed?
      @errors << "Missing public repository #{REPO_NWO}"
      return
    end

    unless latest_sha
      @errors << "Could not determine latest commit for #{topics_repository.nwo} in " +
                 "#{topics_repository.default_branch} branch"
      return
    end

    topic_dirs_to_update = all_topic_directories
    unless dry_run
      topic_dirs_to_update = topic_dirs_to_update.select { |dir| topic_names.include?(dir.name) }
    end

    measure(metric: "import_topic_from_directory_overall", dry_run: dry_run) do
      topic_dirs_to_update.each do |topic_dir|
        measure(metric: "import_topic_from_directory", dry_run: dry_run) do
          import_topic_from_directory(topic_dir, dry_run: dry_run)
        end
      end
    end

    names_to_keep = topic_names_to_keep(all_topic_directories)
    remove_curated_content_except(names_to_keep: names_to_keep, dry_run: dry_run)
  end

  # Public: Returns topic changesets for new topics that are not yet in the database.
  #
  # Returns an Array of TopicChangesets.
  def new_topic_changesets
    @changesets.select(&:new?)
  end

  # Public: Returns topic changesets for existing topics that are in the database but have changes.
  #
  # Returns an Array of TopicChangesets.
  def updated_topic_changesets
    @changesets.select(&:changed?)
  end

  # Public: Returns a count of how many new topics will be created by this import.
  #
  # Run #import with dry_run: true first.
  #
  # Returns an integer.
  def new_count
    new_topic_changesets.size
  end

  # Public: Returns a count of how many existing topics will be updated by this import.
  #
  # Run #import with dry_run: true first.
  #
  # Returns an integer.
  def updated_count
    updated_topic_changesets.size
  end

  # Public: Returns true if any new topics will be created by this import.
  #
  # Run #import with dry_run: true first.
  #
  # Returns a Boolean.
  def any_new?
    new_count > 0
  end

  # Public: Returns true if any existing topics will be updated by this import.
  #
  # Run #import with dry_run: true first.
  #
  # Returns a Boolean.
  def any_updates?
    updated_count > 0
  end

  # Public: Returns true if any topics will be created or updated by this import.
  #
  # Run #import with dry_run: true first.
  #
  # Returns a Boolean.
  def any_changes?
    any_new? || any_updates?
  end

  private

  # Private: Returns a list of topic names that should not have their curated content removed.
  # Run this after new and updated topics have been determined.
  #
  # topic_dirs - a list of topic directories from the github/explore repository
  #
  # Returns an Array of Strings.
  def topic_names_to_keep(topic_dirs)
    measure(metric: "topic_names_to_keep") do
      topic_dirs.pluck(:name) | @changesets.map { |changeset| changeset.topic.name }
    end
  end

  # Private: Determines which topics are curated but not in the given list of names to keep, and
  # wipes their curated content fields.
  def remove_curated_content_except(names_to_keep:, dry_run:)
    all_curated_topic_names = measure(metric: "all_curated_topic_names") do
      Topic.curated.pluck(:name)
    end

    topic_names_to_decurate = all_curated_topic_names - names_to_keep
    return if topic_names_to_decurate.empty?

    measure(metric: "remove_curated_content_from_overall", dry_run: dry_run) do
      topic_names_to_decurate.each_slice(100) do |names_batch|
        remove_curated_content_from(names_batch, dry_run: dry_run)
      end
    end
  end

  # Private: Given a list of topic names, this will remove the curated content from those topics.
  def remove_curated_content_from(topic_names, dry_run:)
    topics = Topic.where(name: topic_names)
    if dry_run
      measure(metric: "remove_curated_content_from", dry_run: true) do
        topics.each do |topic|
          changeset = TopicChangeset.new(topic)
          topic.attributes.merge!(
            Topic::CURATED_FIELDS.map { |f| [f.to_s, nil] }.to_h,
            "featured" => false,
          )

          measure(metric: "changeset_determine_changes", dry_run: true) do
            changeset.determine_changes
          end

          @changesets << changeset
        end
      end
    else
      measure(metric: "remove_curated_content_from", dry_run: false) do
        nilled_fields = Topic::CURATED_FIELDS.map { |field| [field, nil] }.to_h
        topics.update_all(nilled_fields.merge(featured: false))
      end
    end
  end

  def import_topic_from_directory(topic_dir, dry_run:)
    topic_name = topic_dir.name
    metadata, description = read_topic_index_file(topic_name)

    unless metadata.present? && description.present?
      @errors << "Could not read metadata and description for #{topic_name} " +
                 "from #{INDEX_FILE_NAME}"
      return
    end

    topic = Topic.find_by_name(topic_name) || Topic.new(name: topic_name)
    changeset = TopicChangeset.new(topic)

    topic.description = encode_value_if_present(description)
    topic.created_by = encode_value_if_present(metadata["created_by"])
    topic.display_name = encode_value_if_present(metadata["display_name"])
    topic.logo_url = logo_url_from(topic_name, metadata)
    topic.released = encode_value_if_present(metadata["released"])
    topic.short_description = encode_value_if_present(metadata["short_description"])
    topic.url = metadata["url"]
    topic.wikipedia_url = metadata["wikipedia_url"]
    topic.github_url = metadata["github_url"]

    new_aliases = metadata["aliases"]
    new_related = metadata["related"]
    metadata["aliases"] = new_aliases.to_s.split(Topic::ALIAS_DELIMITER).map(&:strip)
    metadata["related"] = new_related.to_s.split(Topic::RELATED_DELIMITER).map(&:strip)

    changeset.determine_changes(metadata.with_indifferent_access)
    anything_to_save = changeset.new? || changeset.changed?
    @changesets << changeset if anything_to_save

    if anything_to_save && !dry_run
      unless topic.save
        @errors.concat topic.errors.full_messages
      end

      topic.update_aliases_from_names(new_aliases || "")
      topic.update_related_topics_from_names(new_related || "")
    end

    @topics[topic.name] = topic
  end

  def latest_sha
    @latest_sha ||= measure(metric: "latest_sha") do
      topics_repository.heads.find(topics_repository.default_branch).try(:target_oid)
    end
  end

  # Private: Returns a list of topic directories.
  #
  # Returns an Array of TreeEntry instances.
  def all_topic_directories
    @_all_topic_directories ||= measure(metric: "all_topic_directories") do
      _id, tree_entries, _truncated = topics_repository.tree_entries(latest_sha, TOPICS_PATH)
      tree_entries.select { |entry| entry.type == "tree" }
    end
  end

  def logo_url_from(topic_name, metadata)
    measure(metric: "logo_url_from") do
      return unless metadata["logo"]

      topic_dir_path = File.join(TOPICS_PATH, topic_name)
      topic_dir = topics_repository.directory(latest_sha, topic_dir_path)
      return unless topic_dir

      tree_history = topic_dir.tree_history
      commit = tree_history.load_or_calculate_single_entry(metadata["logo"])
      return unless commit

      host = "#{GitHub.scheme}://#{GitHub.urls.raw_host_name}"
      path = "/#{topics_repository.nwo}/#{commit.oid}/#{TOPICS_PATH}/" \
             "#{topic_name}/#{metadata["logo"]}"
      host + path
    end
  end

  def encode_value_if_present(value)
    return unless value.present?

    value = value.to_s

    if value.respond_to?(:force_encoding) && value.encoding != ::Encoding::UTF_8
      value.force_encoding("UTF-8")
    end

    value
  end

  def read_topic_index_file(topic_name)
    measure(metric: "read_topic_index_file") do
      path = File.join(TOPICS_PATH, topic_name, INDEX_FILE_NAME)
      entry = topics_repository.blob(latest_sha, path)
      return unless entry && entry.data

      parts = entry.data.split("---", 3)
      return unless parts.length == 3

      _, yaml, body = parts
      metadata = YAML.safe_load(yaml)
      [metadata, body.strip]
    end
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
