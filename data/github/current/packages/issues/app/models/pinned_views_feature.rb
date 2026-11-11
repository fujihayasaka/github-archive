# typed: strict
# frozen_string_literal: true

# Represents the issues pinned views feature
module PinnedViewsFeature
  extend T::Helpers

  PINNED_VIEWS_FLAG = :issue_pinned_views
  INDEX_PAGE_FLAG = :issue_pinned_views_index_page

  sig do
    params(
      entity: T.any(Repository, Organization),
      actor: T.nilable(User)
    ).returns(T::Boolean)
  end
  def self.enabled?(entity, actor: nil)
    actors = [entity, actor]
    if entity.is_a?(Repository) && entity.owner.is_a?(Organization)
      actors << entity.owner
    end
    FeatureFlag.vexi.enabled?(PINNED_VIEWS_FLAG, *actors, default: false)
  end

  sig do
    params(
      entity: T.any(Repository, Organization),
      actor: T.nilable(User)
    ).returns(T::Boolean)
  end
  def self.index_page_enabled?(entity, actor: nil)
    return false unless enabled?(entity, actor: actor)

    actors = [entity, actor]
    if entity.is_a?(Repository) && entity.owner.is_a?(Organization)
      actors << entity.owner
    end
    FeatureFlag.vexi.enabled?(INDEX_PAGE_FLAG, *actors, default: false)
  end
end
