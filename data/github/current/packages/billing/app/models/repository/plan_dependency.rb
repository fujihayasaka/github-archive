# typed: strict
# frozen_string_literal: true

module Repository::PlanDependency
  extend T::Helpers

  requires_ancestor { Repository }

  # Public: Does the root repository plan support a gated feature?
  #
  # Note: We use plan_owner to check permissions and limits instead of owner.
  #       The repository permissions and limits needs to respect the parent repo
  #       permission when forked.
  # Note: We will fallback to a free tier if the `plan_owner` is disabled. That's
  #       what the `fallback_to_free: true` is for. That means, that when checking
  #       for supports/limit api on a repository, we will give the 'free plan'
  #       results if the `plan_owner` was disabled(i.e.: Billing issues)
  #       This fallback is important, because we will be gating repository
  #       functionality with this APIs. Thus, if `plan_owner` stop paying,
  #       it defaults back to the free tier permissions.
  sig { params(feature: Symbol, visibility: Symbol).returns(T::Boolean) }
  def plan_supports?(feature, visibility: self.visibility)
    !!plan_owner&.plan_supports?(feature, visibility: visibility, fallback_to_free: true)
  end

  sig { params(feature: Symbol, visibility: Symbol).returns(Promise[T::Boolean]) }
  def async_plan_supports?(feature, visibility: async_visibility)
    visibility = Promise.resolve(visibility)
    Promise.all([async_plan_owner, visibility]).then do |plan_owner, visibility|
      !!plan_owner&.plan_supports?(feature, visibility: visibility, fallback_to_free: true)
    end
  end

  # Public: The root repository plan's owner limit for a gated feature.
  # See notes for `plans_supports?` method above.
  sig { params(feature: Symbol, visibility: Symbol).returns(Integer) }
  def plan_limit(feature, visibility: self.visibility)
    plan_owner&.plan_limit(feature, visibility: visibility, fallback_to_free: true).to_i
  end

  sig { params(feature: Symbol, visibility: Symbol).returns(Promise[Integer]) }
  def async_plan_limit(feature, visibility: self.visibility)
    async_plan_owner.then do |plan_owner|
      plan_owner&.plan_limit(feature, visibility: visibility, fallback_to_free: true).to_i
    end
  end

  sig { params(user: ::User).returns(T::Boolean) }
  def has_seat_for?(user)
    !at_seat_limit? || member_ids.include?(user.id) || has_invitation_for?(user)
  end

  sig { returns(Integer) }
  def filled_seats
    members_count + invitees.count
  end

  sig { returns(Integer) }
  def seats
    plan_limit(:collaborators)
  end

  sig { returns(Integer) }
  def private_collaborator_seats
    plan_limit(:collaborators, visibility: :private)
  end

  sig { returns(Integer) }
  def available_seats
    [seats - filled_seats, 0].max
  end

  sig { returns(Integer) }
  def available_private_seats
    private_collaborator_seats - filled_seats
  end

  sig { returns(T::Boolean) }
  def at_seat_limit?
    available_seats < 1
  end

  sig { returns(T::Boolean) }
  def part_of_unlimited_plan?
    !!plan_owner&.has_unlimited_private_repositories?
  end

  sig { returns(T::Boolean) }
  def fine_grained_permissions_supported?
    !!(in_organization? && plan_supports?(:fine_grained_permissions))
  end

  sig { returns(String) }
  def next_plan
    T.must(owner).organization? ? "GitHub Team" : "GitHub Pro"
  end
end
