# typed: strict
# frozen_string_literal: true

class MemexTemplate < ApplicationRecord::Domain::Memexes
  extend T::Sig

  MAX_ORGANIZATION_RECOMMENDED_TEMPLATES = 6

  belongs_to :memex_project, required: true
  has_many :memex_projects, \
    foreign_key: :created_with_memex_template_id,
    inverse_of: :created_with_memex_template,
    dependent: :nullify

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  after_destroy :destroy_memex_project_links
  after_update :destroy_organization_memex_project_links, if: %i[active_previously_changed? inactive?]

  sig { returns(T::Boolean) }
  def inactive?
    !active?
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_hash
    {
      updatedAt: created_at&.utc&.iso8601,
      createdAt: created_at&.utc&.iso8601,
      id: id,
      isActive: active?,
    }
  end

  # When a MemexTemplate is marked as inactive we need to remove all Organization MemexProjectLinks to prevent the
  # case that we exceed the number of allowed Organization recommended MemexTemplates should the user re-activate
  # the MemexTemplate.
  sig { void }
  def destroy_organization_memex_project_links
    T.must(memex_project).memex_project_links.for_organizations.destroy_all
  end

  # We cannot normally modify the memex_project_links association or Rails will raise an error so we have to destroy
  # the records through the `memex_project` association.
  sig { void }
  def destroy_memex_project_links
    T.must(memex_project).memex_project_links.destroy_all
  end
end
