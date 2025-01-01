# typed: false
# frozen_string_literal: true

class RepositoryStackRelease < ApplicationRecord::Domain::Repositories
  belongs_to :release
  belongs_to :repository_stack, class_name: "RepositoryStack"

  validate :stack_belongs_to_repository
  validate :user_not_spammy, on: %i[create update], if: :published_on_marketplace?
  validate :has_signed_marketplace_agreement, on: :create, if: :published_on_marketplace?
  validate :user_has_2fa_enabled, on: %i[create update], if: :published_on_marketplace?
  after_create :list_stack_on_marketplace!, if: :published_on_marketplace?
  after_save :list_stack_on_marketplace!, if: :published_on_marketplace?
  after_save :delist_unreleased_stack, unless: :published_on_marketplace?
  after_destroy :delist_unreleased_stack

  scope :published, -> { where(published_on_marketplace: true) }

  attr_writer :actor

  private

  def user_not_spammy
    return unless repository_stack.owner.spammy? || actor_or_author.spammy?
    errors.add :base, "flagged accounts cannot publish stacks"
  end

  def has_signed_marketplace_agreement
    if stack_belongs_to_org?
      validate_org_signed_marketplace_agreement
    else
      validate_user_signed_marketplace_agreement
    end
  end

  def validate_org_signed_marketplace_agreement
    return if repository_stack.org_has_signed_integrator_agreement?(org: repository_stack.repository.owner)

    errors.add :base, "organization must sign latest developer agreement before publishing a stack"
  end

  def validate_user_signed_marketplace_agreement
    return if repository_stack.has_signed_integrator_agreement?(user: actor_or_author)

    errors.add :base, "must sign latest developer agreement before publishing a stack"
  end

  def user_has_2fa_enabled
    return if actor_or_author.two_factor_authentication_enabled?

    errors.add :base, "must have 2FA enabled to publish a stack"
  end

  def stack_belongs_to_repository
    return if release.repository == repository_stack.repository

    errors.add :base, "source must be in the repository"
  end

  def stack_belongs_to_org?
    repository_stack.repository.owner.organization?
  end

  def list_stack_on_marketplace!
    repository_stack.update_from_config!(release.tag_name)
    repository_stack.listed! unless repository_stack.listed?
  end

  def delist_unreleased_stack
    repository_stack.delist_if_unreleased
  end

  # When publishing a release to the Marketplace, we want to consider the user
  # making the update for validating things like 2FA and a signed Marketplace
  # agreement since the release's original author may be a bot.
  def actor_or_author
    @actor || release.author
  end
end
