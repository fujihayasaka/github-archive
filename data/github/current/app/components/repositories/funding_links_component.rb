# typed: strict
# frozen_string_literal: true

class Repositories::FundingLinksComponent < ApplicationComponent
  sig do
    params(
      repository: Repository,
      current_user_can_push: T::Boolean,
      funding_links: T.nilable(FundingLinks),
      preview: T::Boolean,
      in_overlay: T::Boolean,
    ).void
  end
  def initialize(repository:, current_user_can_push:, funding_links: nil, preview: false, in_overlay: false)
    @repository = repository
    @funding_links = funding_links
    @current_user_can_push = current_user_can_push
    @preview = preview
    @in_overlay = in_overlay
  end

  private

  sig { returns Repository }
  attr_reader :repository

  sig { returns T::Boolean }
  def render?
    GitHub.sponsors_enabled?
  end

  sig { returns FundingLinks }
  memoize def funding_links
    @funding_links || repository.funding_links
  end

  sig { returns T::Boolean }
  def previewing?
    @preview
  end

  sig { returns T::Boolean }
  def in_overlay?
    @in_overlay
  end

  sig { returns T::Boolean }
  def current_user_can_push?
    @current_user_can_push
  end
end
