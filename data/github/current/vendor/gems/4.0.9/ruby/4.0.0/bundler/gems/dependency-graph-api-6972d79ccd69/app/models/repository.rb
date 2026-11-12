class Repository < ApplicationRecord
  self.table_name = "dg_repositories"

  has_many :manifests,
    dependent: :destroy

  has_many :abstract_dependencies,
    class_name: "AbstractRepositoryDependency",
    dependent: :destroy

  has_one :star_count_assoc,
    class_name: "StarCount",
    foreign_key: :github_repository_id,
    primary_key: :github_repository_id,
    dependent: :destroy

  has_many :mapped_packages,
    class_name: "Package",
    foreign_key: :repository_id,
    primary_key: :github_repository_id

  scope :owned_by, -> (owner) { where(github_owner_id: owner) }
  scope :public_repos, -> () { where(public: true) }
  scope :with_github_repository_id, -> (ids) { where(github_repository_id: ids) }

  def star_count
    star_count_assoc&.star_count || 0
  end

  # This is used by feature-flags-client gem to identify the actor for the call to feature flags service.
  def twirp_actor_id
    "Repository:#{github_repository_id}"
  end
end
