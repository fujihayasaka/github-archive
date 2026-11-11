# typed: false
# frozen_string_literal: true

class RepositoryActionRelease < ApplicationRecord::Domain::Repositories
  include GitHub::Relay::GlobalIdentification

  belongs_to :repository_action
  belongs_to :release
  validate :action_belongs_to_repository
  validate :user_not_spammy, on: %i[create update], if: :published_on_marketplace?
  validate :has_signed_marketplace_agreement, on: :create, if: :published_on_marketplace?
  validate :user_has_2fa_enabled, on: %i[create update], if: :published_on_marketplace?
  after_create :list_action_on_marketplace!, if: :published_on_marketplace?
  after_save :list_action_on_marketplace!, if: :published_on_marketplace?
  after_save :delist_unreleased_action, unless: :published_on_marketplace?
  after_destroy :delist_unreleased_action

  scope :published, -> { where(published_on_marketplace: true) }

  attr_writer :actor

  private

  def user_not_spammy
    return unless repository_action.owner.spammy? || actor_or_author.spammy?
    errors.add :base, "flagged accounts cannot publish Actions"
  end

  def has_signed_marketplace_agreement
    if action_belongs_to_org?
      validate_org_signed_marketplace_agreement
    else
      validate_user_signed_marketplace_agreement
    end
  end

  def validate_org_signed_marketplace_agreement
    return if repository_action.org_has_signed_integrator_agreement?(org: repository_action.repository.owner)

    errors.add :base, "organization must sign latest developer agreement before publishing an Action"
  end

  def validate_user_signed_marketplace_agreement
    return if repository_action.has_signed_integrator_agreement?(user: actor_or_author)

    errors.add :base, "must sign latest developer agreement before publishing an Action"
  end

  def user_has_2fa_enabled
    return if actor_or_author.two_factor_authentication_enabled?

    errors.add :base, "must have 2FA enabled to publish an Action"
  end

  def action_belongs_to_repository
    return if release.repository == repository_action.repository

    errors.add :base, "source must be in the repository"
  end

  def action_belongs_to_org?
    repository_action.repository.owner.organization?
  end

  def list_action_on_marketplace!
    repository_action.update_from_config!
    unless repository_action.listed?
      delist_dockerfile_action!
      delist_listed_action_if_present!
      repository_action.listed!
    end
  end

  # If the user has an old Dockerfile Action. We help them replace it with a new action.yml Action.
  def delist_dockerfile_action!
    existing_dockerfile_action = RepositoryAction.where(path: "Dockerfile", repository: repository_action.repository).where.not(id: repository_action.id).first
    return unless existing_dockerfile_action

    existing_dockerfile_action.delisted!
    existing_dockerfile_action.update(slug: nil)
  end

  def delist_unreleased_action
    repository_action&.delist_if_unreleased
  end

  # If the user has another RepositoryAction listed, we delist it so we can list the current one.
  def delist_listed_action_if_present!
    listed_action = repository_action.repository.listed_action

    if listed_action.present?
      listed_action.delisted!
      listed_action.update(slug: nil)
    end
  end

  # When publishing a release to the Marketplace, we want to consider the user
  # making the update for validating things like 2FA and a signed Marketplace
  # agreement since the release's original author may be a bot.
  def actor_or_author
    @actor || release.author
  end
end
