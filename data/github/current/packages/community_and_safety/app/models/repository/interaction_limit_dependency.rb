# typed: true
# frozen_string_literal: true

module Repository::InteractionLimitDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ::Repository }

  included do
    T.bind(self, T.class_of(Repository))

    has_one :repo_interaction_limit, -> { T.unsafe(self).on_repository.not_expired }, class_name: "InteractionLimit", dependent: :destroy
  end

  def enable_repo_interaction_limit(restriction:, expires_at:)
    InteractionLimit.transaction do
      # There may be an existing limit that has expired, or where we're extending the expiration
      disable_repo_interaction_limit

      self.create_repo_interaction_limit!(user_id: self.owner_id, restriction: restriction, expires_at: expires_at)
    end
  end

  def disable_repo_interaction_limit
    InteractionLimit.on_repository.where(repository: self).delete_all
  end
end
