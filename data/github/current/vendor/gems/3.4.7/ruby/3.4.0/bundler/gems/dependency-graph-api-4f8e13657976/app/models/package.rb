class Package < ApplicationRecord
  self.table_name = "dg_packages"

  extend PackageManagerScoping

  include WhereIn

  scope :alphabetical, -> { order(Arel.sql("lower(#{table_name}.name)")) }
  scope :for_repositories, -> (ids) { where(repository_id: ids) }
  scope :github_repositories, -> { where.not(repository_id: nil) }
  scope :max_repository_id_certainty, -> { maximum(:repository_id_certainty) }
  scope :most_certain_repository_id_first, -> { order(repository_id_certainty: :desc) }
  scope :with_name, -> (name) { where(name: name) }
  scope :with_no_repository_mapping, -> { where(repository_id_certainty: 0) }
  scope :with_repository_id_certainty_of_at_least, -> (certainty) { where("repository_id_certainty >= ?", certainty) }
  scope :most_recently_created, -> { order(created_at: :desc).first }
  scope :most_recently_published, -> { order(last_published_at: :desc).first }
  scope :most_recently_updated, -> { order(updated_at: :desc).first }
  scope :repository_owned_by, -> (owner) { joins(:repository).merge(Repository.owned_by(owner)) }

  restrict_type_of :package_manager, to: Types::PackageManager

  # All releases of this package.
  #
  # returns ActiveRecord::Relation<PackageRelease>
  has_many :releases,
    class_name: "PackageRelease",
    dependent: :destroy

  has_many :abstract_dependencies,
    class_name: "AbstractPackageDependency",
    foreign_key: :dependent_id,
    dependent: :destroy

  has_one :repository,
    primary_key: :repository_id,
    foreign_key: :github_repository_id

  validates :name, presence: true

  alias_attribute :github_repository_id, :repository_id

  delegate :github_owner_id, to: :repository

  # Note: this shouldn't need an explict prefix, but I think the temporary
  # `ignored_columns` definition is preventing a default prefix being used.
  delegate :nwo, to: :repository, prefix: :repository, allow_nil: true

  def self.most_dependents_first
    sql = <<~SQL
      LEFT OUTER JOIN #{Views::AbstractRepositoryDependencyCount.table_name} dependent_counts
        ON dependent_counts.package_name = #{table_name}.name
          AND dependent_counts.package_manager = #{table_name}.package_manager
    SQL

    joins(sql).order(Arel.sql("COALESCE(dependent_counts.dependent_count, 0) DESC"))
  end

  def dependencies
    raise "`dependencies` is only defined on specific package releases. " + \
      "Try package.latest_version.dependencies"
  end

  def latest_version
    releases.latest
  end
end
