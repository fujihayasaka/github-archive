# typed: true
# frozen_string_literal: true

module User::InteractionLimitDependency
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ::User }

  included do
    T.bind(self, T.class_of(User))

    has_one :repo_interaction_limit, -> { T.unsafe(self).on_repository.not_expired.where(repository: nil) }, class_name: "InteractionLimit", dependent: :destroy
    has_one :user_interaction_limit, -> { T.unsafe(self).on_user.not_expired }, class_name: "InteractionLimit", dependent: :destroy
  end

  # Sets the specified global limit on repos owned by this account until the specified expiration time.
  def enable_repo_interaction_limit(restriction:, expires_at:)
    InteractionLimit.transaction do
      # There may be an existing limit that has expired, or where we're extending the expiration
      disable_repo_interaction_limit

      create_repo_interaction_limit!(restriction: restriction, expires_at: expires_at)
    end
  end

  # Removes global limits on repos owned by this account.
  def disable_repo_interaction_limit
    InteractionLimit.on_repository.where(user: self, repository: nil).delete_all
  end

  # Removes any user interaction limits associated with this account.
  def allow_user_interactions
    InteractionLimit.on_user.where(user: self).delete_all
  end

  def disallow_user_interactions(expires_at:)
    InteractionLimit.transaction do
      # There may be an existing limit that has expired, or where we're extending the expiration
      allow_user_interactions

      create_user_interaction_limit!(expires_at: expires_at)
    end
  end
end
