# typed: true
# frozen_string_literal: true

module InteractionBanValidation
  extend ActiveSupport::Concern
  include ActionView::Helpers::DateHelper
  extend T::Helpers

  requires_ancestor { ActiveRecord::Base }

  abstract!

  sig { abstract.returns(T.nilable(User)) }
  def user; end

  sig { abstract.returns(T.nilable(Repository)) }
  def repository; end

  # Public: Determine if the author is allowed to make comments
  def user_can_interact
    validate_can_interact(user)
  end

  def editor_can_interact
    # This is applicable for classes that include `UserContentEditable` module
    validate_can_interact(T.unsafe(self).editor)
  end

  private

  def validate_can_interact(actor)
    return unless actor && (repo = repository)
    return unless GitHub.interaction_limits_enabled?
    return if repo.pushable_by?(actor)
    restricted_by_repository_checks(actor) unless repo.private?
    return if User::InteractionAbility.interaction_allowed?(user: actor, user_can_push: false)
    owner = repo.owner
    return if owner.is_a?(Organization) && owner.member?(actor)

    expiry = User::InteractionAbility.ban_expiry(actor).in_time_zone
    errors.add(
      :base,
      "ability has been suspended for #{distance_of_time_in_words(DateTime.now, expiry)}. If you believe this is in error, please contact GitHub support",
    )
  end

  def restricted_by_repository_checks(actor)
    interaction_ability = RepositoryInteractionAbility.new(repository)
    active_limit = interaction_ability.overall_active_limit
    return if active_limit == :no_limit
    return if RepositoryInteractionAbility.user_exempt?(active_limit, repository, actor)

    case active_limit
    when :sockpuppet_disallowed
      errors.add(
        :base,
        "could not be created. Interactions on this repository have been restricted from new users.",
      )
    when :contributors_only
      errors.add(
        :base,
        "could not be created. Interactions on this repository have been restricted to prior contributors only.",
      )
    when :collaborators_only
      errors.add(
        :base,
        "could not be created. Interactions on this repository have been restricted to collaborators only.",
      )
    end
  end
end
