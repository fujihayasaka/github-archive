# typed: false
# frozen_string_literal: true

class CollectionImporter
  ITEM_DELIMITER = ","
  BATCH_SIZE = 100

  attr_reader :errors

  def initialize(explore_repository_file_reader)
    @explore_repository_file_reader = explore_repository_file_reader
    @item_factory = CollectionItemFactory.new
  end

  # Public: Create and update Collection records from the latest data in the github/explore repo.
  # Any collection that is no longer in github/explore will have its curated content wiped.
  #
  # dry_run - set to true if no writes should be made; useful for previewing changes
  # collection_slugs - a list of String collection slugs names that should be updated; ignored when
  #                    dry_run is true; only used to determine setting curated content, not wiping it
  #
  # Returns nothing.
  def import(dry_run:, collection_slugs: [], force_import: false)
    @changesets = []
    @errors = []
    collection_dirs_to_update = []

    begin
      collection_dirs_to_update = all_collection_directories
    rescue RuntimeError => e
      @errors << e.message
    end

    return ImportResult.new(@changesets, @errors) if !@errors.empty?
    unless dry_run
      collection_dirs_to_update = collection_dirs_to_update.select do |dir|
        collection_slugs.include?(dir.name)
      end
    end
    collection_dirs_to_update.each do |collection_dir|
      import_collection_from_directory(collection_dir, dry_run: dry_run, force_import: force_import)
    end

    create_update_changeset_for_deletion(collection_dirs_to_update, collection_slugs, dry_run)
    ImportResult.new(@changesets, @errors)
  end

  private

  def import_collection_from_directory(collection_dir, dry_run:, force_import:)
    slug = force_encoding(collection_dir.name)

    metadata, description = @explore_repository_file_reader.read_index_file(slug)
    unless metadata.present? && description.present?
      @errors << "Could not read metadata and description for #{slug}"
      return
    end

    collection = build_collection(slug, description, metadata)
    collection_item_slugs = extract_collection_item_slugs(metadata)

    changeset = CollectionChangeset.new(collection, collection_item_slugs)
    changeset.determine_changes!

    if changeset.new? || changeset.changed? || force_import
      @changesets << changeset

      unless dry_run
        collection.items = build_collection_items(collection_item_slugs, slug)
        collection.save

        if collection.errors.present?
          @errors.concat collection.errors.full_messages
        end
      end
    end
  end

  def extract_collection_item_slugs(metadata)
    metadata["items"].map do |item|
      force_encoding(item).strip
    end
  end

  def extract_image_url(slug, metadata)
    image_name = force_encoding(metadata["image"])

    @explore_repository_file_reader.url_from(slug, image_name)
  end

  def build_collection(slug, description, metadata)
    (ExploreCollection.find_by_slug(slug) || ExploreCollection.new(slug: slug)).tap do |collection|
      collection.image_url = extract_image_url(slug, metadata)

      collection.description = force_encoding(description)
      collection.created_by = force_encoding(metadata["created_by"])
      collection.display_name = force_encoding(metadata["display_name"])
    end
  end

  def build_collection_items(collection_item_slugs, collection_slug)
    collection_items = []

    collection_item_slugs.each do |collection_item_slug|
      begin
        collection_item = @item_factory.build_from_slug(collection_item_slug)

        if collection_item
          collection_items << collection_item
        else
          @errors << "Unable to find #{collection_item_slug} data for collection #{collection_slug}"
        end
      rescue RuntimeError => e
        @errors << "#{e.message} #{item_slug}"
      end
    end

    collection_items
  end

  def create_update_changeset_for_deletion(collection_dirs_to_update, collection_slugs, dry_run)
    existing_collection_slugs = ExploreCollection.pluck(:slug)
    names_to_remove = existing_collection_slugs - collection_dirs_to_update.map(&:name)

    unless dry_run
      names_to_remove = names_to_remove & collection_slugs
    end

    names_to_remove.each_slice(BATCH_SIZE) do |names_batch|
      collections = ExploreCollection.where(slug: names_batch)

      if dry_run
        create_deletion_changesets(collections)
      else
        collections.each do |collection|
          changeset = CollectionChangeset.new(collection)
          changeset.determine_changes!

          @changesets << changeset
        end

        collections.destroy_all
      end
    end
  end

  def create_deletion_changesets(collections)
    collections.each do |collection|
      collection.attributes.each_key do |key|
        collection[key] = nil
      end

      changeset = CollectionChangeset.new(collection)
      changeset.determine_changes!

      @changesets << changeset
    end
  end

  def all_collection_directories
    @explore_repository_file_reader.all_directories
  end

  def force_encoding(value)
    return unless value.present?

    value = value.to_s
    value.force_encoding("UTF-8")
  end
end
