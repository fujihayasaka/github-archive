# typed: strict
# frozen_string_literal: true

class RepositoryGroup < ApplicationRecord::Domain::Repositories
  extend T::Sig
  extend T::Helpers

  belongs_to :owner, polymorphic: true
  has_many :group_maps, class_name: "RepositoryGroupMap", dependent: :destroy
  has_many :repository_group_settings, dependent: :destroy
  has_many :repositories, through: :group_maps

  # group_path format is '' or 'foo' or 'foo/bar'
  GROUP_PATH_REGEX = /\A(|[a-zA-Z0-9\.\-\_]+(\/[a-zA-Z0-9\.\-\_]+)*)\z/

  validates_presence_of :owner
  validates :group_path,
    format: { with: GROUP_PATH_REGEX, message: "%{value} format is invalid" },
    allow_nil: false
  validate :validate_group_path

  sig { void }
  def validate_group_path
    # maximum depth is 7, so only 6 slashes are allowed
    if group_path.count("/") > 6
      errors.add(:group_path, "is too deep")
    end
  end

  sig { returns(T.nilable(String)) }
  def parent_path
    return nil if group_path.empty?
    index = group_path.rindex("/")
    T.must(index ? group_path[0...index] : "")
  end

  # remove this group, and re-parent any repos into the parent group
  sig { returns(T.untyped) }
  def remove
    # raise if this is the root group
    raise ArgumentError, "Cannot delete the root group" if group_path.empty?

    # next find parent groups, or create them
    index = group_path.rindex("/")
    parent_path = T.must(index ? group_path[0...index] : "")
    parent = RepositoryGroup.find_by!(owner:, group_path: parent_path)

    # re-parent all repos in this group to the parent group
    group_maps.update_all(repository_group_id: parent.id)
    self.destroy!
  end

  sig { params(new_group_path: String).void }
  def rename(new_group_path)
    # first verify the new name doesn't exist
    if RepositoryGroup.exists?(owner: owner, group_path: new_group_path)
      raise ArgumentError, "Group already exists"
    end

    # next find parent groups, or create them
    index = new_group_path.rindex("/")
    parent_path = T.must(index ? new_group_path[0...index] : "")
    parent = RepositoryGroup.find_or_create_group(owner:, group_path: parent_path)

    leaf_path = index ? new_group_path[index + 1..-1] : new_group_path

    # recursive call to ourselves to get the parent group
    parent_group = RepositoryGroup.find_or_create_group(owner: owner, group_path: parent_path)

    # Now that we have the parent group, modify new_group_path to match the parent's case
    new_group_path = index ? "#{parent_group.group_path}/#{leaf_path}" : leaf_path

    # get a list of all affected groups, including self
    groups = RepositoryGroup.where(owner: owner)
    .where("CONCAT(repository_groups.group_path, '/') LIKE ?", group_path + "/%")

    groups.map do |group|
      # replace the old path with the new one.
      # this does a string replace
      group.group_path[group_path] = new_group_path
    end

    transaction do
      groups.each do |group|
        group.save!
      end
    end
  end

  # When creating a group, make sure that the parent group exists, and if not create it.
  # Also make sure the casing for the parents in this group_path matches the actual parents.
  # ie, if foo exists and you want to create FOO/BAR, you'll get back foo/BAR
  # Returns the group for this group_path.
  # NOTE: It may have a different casing than provided, if it was created earlier
  sig { params(owner: T.untyped, group_path: String).returns(RepositoryGroup) }
  def self.find_or_create_group(owner:, group_path:)
    # handle the special case for the root group
    return RepositoryGroup.find_or_create_by!(owner: owner, group_path: "") if group_path.empty?

    # if the group exists, return it
    group = RepositoryGroup.find_by(owner: owner, group_path: group_path)
    return group if group

    # If the group doesn't exist, we need to create it,
    # and we need to make sure we use any existing casing for the parent group.
    # So find (or create) the parent groups so we know their casing.
    index = group_path.rindex("/")
    parent_path = T.must(index ? group_path[0...index] : "")
    leaf_path = index ? group_path[index + 1..-1] : group_path

    # recursive call to ourselves to get the parent group
    parent_group = RepositoryGroup.find_or_create_group(owner: owner, group_path: parent_path)

    # Now that we have the parent group, we can create the new group.
    # Modify our group_path to match the parent's
    new_path = index ? "#{parent_group.group_path}/#{leaf_path}" : leaf_path
    RepositoryGroup.create!(owner: owner, group_path: new_path)
  end

  sig { params(repository: Repository, group_path: String).returns(T::Boolean) }
  def self.repository_in_group?(repository, group_path)
    return false if repository.group.nil? # repo is not in a group
    return true if group_path.blank? # group is the root, so all repos are in it
    (repository.group_path + "/").start_with?(group_path + "/")
  end

  sig { params(owner: T.untyped).returns(T::Enumerable[Repository]) }
  def self.repositories_with_no_group(owner)
    Repository.active.includes(:group_map).where(owner: owner).where(repository_group_maps: { id: nil })
  end

  sig { params(owner: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
  def self.repository_summary(owner)
    summary = {}

    # load all the groups
    raw_groups = RepositoryGroup.where(owner: owner).order(group_path: :asc).pluck(:group_path, :id)

    if raw_groups.empty?
      # create a dummy root group
      initialize_group(summary, "", nil)
    else
      raw_groups.each do |group_path, group_id|
        initialize_group(summary, group_path, group_id)
      end
    end

    # Load all repos and put them into their respective groups
    raw_repos = Repository.active
      .left_outer_joins(group_map: :repository_group)
      .where(owner: owner)
      .pluck(:group_path, :name, :id)

    raw_repos.each do |group_path, name, id|
      group_path ||= ""
      summary[group_path][:direct_count] += 1
      summary[group_path][:repos] << { name: name, id: id }
      # bump the total count on this group and all parent groups too
      add_to_total(summary, group_path)
    end
    summary
  end

  sig { params(summary: T::Hash[T.untyped, T.untyped], group_path: T.nilable(String)).void }
  private_class_method def self.add_to_total(summary, group_path)
    if summary[group_path].nil?
      # this shouldn't happen that a parent group is completely missing, but just in case add a dummy entry
      initialize_group(summary, group_path, nil)
    end

    summary[group_path][:total_count] += 1

    # group_path is nil for the no group, "" for root group
    return if group_path.nil? || group_path.blank?

    # Recursively bump the repo count on this parent group
    index = group_path.rindex("/")
    parent_path = T.must(index ? group_path[0...index] : "")
    add_to_total(summary, parent_path)
  end

  sig { params(summary: T::Hash[T.untyped, T.untyped], group_path: T.nilable(String), group_id: T.nilable(Integer)).void }
  private_class_method def self.initialize_group(summary, group_path, group_id)
    summary[group_path] = {}
    summary[group_path][:direct_count] = 0
    summary[group_path][:total_count] = 0
    summary[group_path][:repos] = []
    summary[group_path][:group_id] = group_id
  end

  # Returns all repositories that are in this group, or inherit from this group (ie a subgroup)
  # Warning: This could be a huge number of repositories!
  # For batching, use the repository_batch method instead
  sig { returns(T::Enumerable[Repository]) }
  def repositories_under
    query = Repository.active
      .joins(group_map: :repository_group)
      .where(owner: owner)
    if group_path.present?
      query = query.where("CONCAT(repository_groups.group_path, '/') LIKE ?", group_path + "/%")
    end
    query
  end

  # Finds all repositories that are in this group, or inherit from this group (ie a subgroup)
  # Returns an array with two elements
  # 1. An array of repository ids
  # 2. A watermark to pass back in subsequent calls when calling this method in batches.
  sig { params(watermark: T.nilable(Integer), batch_size: T.nilable(Integer)).returns([T::Array[Integer], Integer]) }
  def repository_batch(watermark: 0, batch_size: 1000)
    watermark = 0 if watermark.nil? || watermark < 0 || !watermark.is_a?(Integer)
    batch_size = 1000 if batch_size.nil? || batch_size < 1 || !batch_size.is_a?(Integer)

    query = RepositoryGroup
      .joins(:repositories)
      .where(owner: owner)
      .where(repositories: { active: true })
      .where("repository_group_maps.id > ?", watermark)
      .order("repository_group_maps.id" => :asc)
      .limit(batch_size)

    if group_path.present?
      query = query.where("CONCAT(repository_groups.group_path, '/') LIKE ?", group_path + "/%")
    end
    results = query.pluck("repositories.id", "repository_group_maps.id")
    repo_ids = results.map(&:first)
    watermark = results.last&.last || 0
    [repo_ids, watermark]
  end
end
