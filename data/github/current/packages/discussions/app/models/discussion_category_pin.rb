# typed: strict
# frozen_string_literal: true

# A given discussion can be pinned in a given category.
# These are different than DiscussionSpotlights, which are global across a repo/org
class DiscussionCategoryPin < ApplicationRecord::Domain::Discussions
  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain required: true
  belongs_to :pinned_by, class_name: "User", required: true
  belongs_to :discussion, required: true
  belongs_to :category, required: true, class_name: "DiscussionCategory"

  before_validation :set_repository
  before_validation :set_category

  validates :discussion, uniqueness: { scope: :category, message: "is already pinned to this category" }

  sig { params(repo: Repository, category: DiscussionCategory).returns(T.untyped) }
  def self.by_repo_and_category(repo:, category:)
    where(repository: repo, category: category)
  end

  sig { params(repo: Repository).returns(T.untyped) }
  def self.for_repository(repo)
    where(repository: repo)
  end

  sig { params(category: DiscussionCategory).returns(T.untyped) }
  def self.for_category(category)
    where(category: category)
  end

  sig { params(discussion: Discussion).returns(T.untyped) }
  def self.for_discussion(discussion)
    where(discussion: discussion)
  end

  private

  sig { void }
  def set_repository
    self.repository = discussion&.repository
  end

  sig { void }
  def set_category
    self.category = discussion&.category
  end
end
