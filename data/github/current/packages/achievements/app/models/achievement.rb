# typed: true
# frozen_string_literal: true

class Achievement < ApplicationRecord::Domain::Achievements
  include GitHub::Memoizer

  belongs_to :user
  belongs_to :unlocking_model, polymorphic: true

  validates :user, presence: true
  validates :unlocking_model, presence: true, unless: :has_dynamic_unlocking_model?
  validates :unlocking_oid, presence: true, if: -> (achievement) { achievement.achievable&.needs_unlocking_oid? }
  validates(
    :achievable_slug,
    inclusion: { in: Achievable.known_slugs },
    presence: true,
    uniqueness: { scope: %i[user_id tier visibility] },
  )
  validates :tier, presence: true

  validate :has_valid_tier, if: :achievable
  validate :has_acceptable_unlocking_model, if: :achievable

  after_commit :instrument_creation_event, on: :create

  enum :visibility, {
    public_scope: 0,
    private_scope: 1,
  }

  scope :with_slug, -> (slug) { where(achievable_slug: slug) }
  scope :with_tier, -> (tier) { where(tier: tier) }
  scope :with_visibility, -> (visibility) { visibility == :PRIVATE ? private_scope : public_scope }
  scope :unseen, -> { where(seen_at: nil) }
  scope :visible, -> { where(hidden: false) }

  def visible?(user)
    user&.id == user_id || !hidden?
  end

  def platform_type_name
    @platform_type_name || "AchievementTier"
  end

  def platform_type_name=(name)
    @platform_type_name = name
  end

  batch_method(:safe_user) do |achievements|
    GitHub::PrefillAssociations.prefill_associations(achievements, :user)
    achievements.index_with { |achievement| achievement.user || User.ghost }
  end

  def achievable
    Achievable.with_slug(achievable_slug)
  end

  def description_template(locale: "en")
    achievable.tier(tier).description_template(locale: locale)
  end

  def description_needs_unlocking_model?
    Achievable::SubstitutedText.needs_unlocking_model?(description_template)
  end

  def unlocking_explanation_template(locale: "en")
    achievable.unlocking_explanation_template(locale: locale)
  end

  def unlocking_commit
    return nil unless unlocking_oid && unlocking_model

    unlocking_model.commits.find(unlocking_oid)
  rescue GitRPC::Timeout, GitRPC::ObjectMissing
    nil
  end

  # Public: Determine if this Achievement tier has been seen by the awarded user.
  #
  # Returns a Boolean.
  def unseen?
    seen_at.nil?
  end

  # Public: The opposite of unseen?.
  def seen?
    seen_at.present?
  end

  # Public: Return the highest-earned Achievement of this achievable for this user and visibility.
  def highest_tier_achievement
    return self if tier == achievable.highest_tier

    self.class.where(user_id: user_id, visibility: visibility)
      .with_slug(achievable_slug)
      .order(tier: :desc)
      .first
  end

  # Public: Encode achievement progress into a string section. This is used to compactly store denormalized
  # Achievement progress in UserMetadata for efficient display on the user profile.
  #
  # Returns a String.
  def to_slug_and_tier
    "#{achievable_slug}:#{tier}"
  end

  # Public: Retrieve the unlocking model for this achievement tier. If the Achievable specifies a dynamic unlocking
  # model spec, its unlocking model spec block will be used to locate the unlocking model at first access and memoize
  # the result. Otherwise, the underlying database relation will be loaded through normal ActiveRecord mechanisms.
  def unlocking_model
    return dynamic_unlocking_model if has_dynamic_unlocking_model?
    super # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def async_unlocking_model
    return async_batch_dynamic_unlocking_model if has_dynamic_unlocking_model?
    super
  end

  # Public: Access the logical type of the unlocking_model. If the Achievable specifies a dynamic unlocking model
  # spec, this will be the type configured in the spec instantiation. Otherwise, this is a normal ActiveRecord
  # column read.
  def unlocking_model_type
    return achievable.accepted_unlocking_model_types.sole if has_dynamic_unlocking_model?
    super
  end

  UNLOCKING_MODEL_REPO_RELATIONS = {
    "CommitComment" => :repository,
    "Commit" => :repository,
    "DiscussionComment" => :repository,
    "Discussion" => :repository,
    "DiscussionPost" => { team: :organization },
    "DiscussionPostReply" => { discussion_post: { team: :organization } },
    "IssueComment" => :repository,
    "Issue" => :repository,
    "PullRequest" => :repository,
    "PullRequestReviewComment" => :repository,
    "PullRequestReview" => :repository,
    "Release" => :repository,
    "RepositoryAdvisoryComment" => { repository_advisory: :repository },
    "RepositoryAdvisory" => :repository,
    "Repository" => :itself,
  }

  UNLOCKING_MODEL_OWNER_RELATIONS = {
    "DiscussionPost" => { team: :organization },
    "DiscussionPostReply" => { discussion_post: { team: :organization } },
  }.freeze

  UNLOCKING_MODEL_OWNERLESS = %w[NilClass Sponsorship AchievementRepositoryList].freeze

  batch_method(:unlocking_model_owner_opted_out?) do |achievements|
    GitHub::PrefillAssociations.prefill_associations(achievements, :unlocking_model)
    achievements_by_model = achievements.to_h { |achievement| [achievement.unlocking_model, achievement] }
    models = achievements_by_model.keys

    results_by_achievement = {}
    opt_out_promises = []

    models.group_by { |model| UNLOCKING_MODEL_REPO_RELATIONS[model.class.name] }.each do |relation, models|
      next if relation.nil?
      GitHub::PrefillAssociations.prefill_associations(models, relation) unless relation == :itself

      repos_by_model = models.index_with { |model| follow_relation(model, relation) }

      repos_by_model.each do |model, repo|
        achievement = achievements_by_model.fetch(model)

        # If we can't reach the repo, assume they "opted out" to be safe.
        if repo.nil?
          results_by_achievement[achievement] = true
          next
        end

        # Only unlocking models in private repositories are excluded by owner opt-out.
        if repo.public?
          results_by_achievement[achievement] = false
          next
        end

        opt_out_promises << repo.async_owner.then do |owner|
          # If we can't reach the owner, assume they "opted out" to be safe.
          if owner.nil?
            next results_by_achievement[achievement] = true
          end

          owner.profile_settings.async_all_private_projects_opted_out_of_achievements_tracking?.then do |opted_out|
            results_by_achievement[achievement] = opted_out
          end
        end
      end
    end

    models.group_by { |model| UNLOCKING_MODEL_OWNER_RELATIONS[model.class.name] }.each do |relation, models|
      next if relation.nil?
      GitHub::PrefillAssociations.prefill_associations(models, relation) unless relation == :itself

      models.each do |model|
        achievement = achievements_by_model.fetch(model)
        owner = follow_relation(model, relation)

        # If the owner is missing, assume they "opted out" to be safe.
        if owner.nil?
          results_by_achievement[achievement] = true
          next
        end

        opt_out_promises << owner.profile_settings.async_all_private_projects_opted_out_of_achievements_tracking?.then do |opted_out|
          results_by_achievement[achievement] = opted_out
        end
      end
    end

    # Ownerless models can never be "opted-out".
    models.select { |model| UNLOCKING_MODEL_OWNERLESS.include?(model.class.name) }.each do |model|
      achievement = achievements_by_model.fetch(model)
      results_by_achievement[achievement] = false
    end

    Promise.all(opt_out_promises).sync if opt_out_promises.any?

    results_by_achievement
  end

  # Public: Temporary compatibility shim. Prefer #unlocking_model.
  def unlockings
    return [] unless has_dynamic_unlocking_model?
    unlocking_model
  end

  delegate :display_name, :has_dynamic_unlocking_model?, to: :achievable, allow_nil: true

  private

  # Private: Retrieve and memoize the unlocking models associated with a batch of Achievements.
  batch_method(:dynamic_unlocking_model) do |achievements|
    models = {}
    achievements.group_by(&:achievable).each do |achievable, achievements|
      fetched_models = achievable&.fetch_dynamic_unlocking_models(achievements)
      models.merge!(fetched_models)
    end
    models
  end

  private_class_method def self.follow_relation(model, relation)
    return nil if relation == :ownerless || model.nil?

    case relation
    when Symbol
      model.public_send(relation)
    when Array
      follow_relation(model, relation.sole)
    when Hash
      current_relation, next_relation = relation.to_a.sole
      next_model = model.public_send(current_relation)
      follow_relation(next_model, next_relation)
    else
      raise "Unexpected element in PARENT_OBJECT_RELATIONS: #{current_relation.inspect}"
    end
  end

  def has_valid_tier
    return if tier.in? achievable.tiers

    errors.add(:tier, "is not included in the achievable tiers")
  end

  def has_acceptable_unlocking_model
    if achievable.has_dynamic_unlocking_model?
      raw_unlocking_model_type = read_attribute(:unlocking_model_type)
      return if raw_unlocking_model_type.blank?

      errors.add(:unlocking_model,
        "is #{raw_unlocking_model_type}, can't be provided for #{achievable.display_name}")
    else
      return if achievable.accepted_unlocking_model_types.include?(unlocking_model_type)

      errors.add(:unlocking_model,
        "is #{unlocking_model_type}, not one of the expected types " +
        achievable.accepted_unlocking_model_types.join(", "))
    end
  end

  def instrument_creation_event
    # Emit Hydro event
    GlobalInstrumenter.instrument "achievement.create", {
      achievement: self,
    }
  end
end
