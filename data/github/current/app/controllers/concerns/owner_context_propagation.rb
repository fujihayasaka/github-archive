# typed: strict
# frozen_string_literal: true

# Sets the owner context for shard boundary detection.
#
# Include this concern in ApplicationController to register a single
# `before_action :propagate_owner_context` for every request.
#
# Controller tiers that know the owner override `owner_context_identifier`:
#   - Orgs::Controller        → resolves from this_organization
#   - RepositoryControllerMethods → resolves from current_repository / owner
#
# The owner context is used by the shard boundary detection system (Steps 3-8)
# to compare query targets against the expected owner for the current request.
# Routes that don't override (dashboard, explore, search, admin) leave
# the identifier nil, which the checker treats as `no_context` — safe, log-only.
module OwnerContextPropagation
  extend ActiveSupport::Concern

  private

  # Resolves the owner and sets it on the request context.
  # Subclasses/modules override `owner_context_identifier` to supply the owner.
  sig { void }
  def propagate_owner_context
    return unless owner_context_propagation_enabled?

    GH.context.owner.id = owner_context_identifier
  end

  # Returns the owner id for the current request, or nil if unknown.
  # Override in controller tiers that can resolve an owner.
  sig { returns(T.nilable(Integer)) }
  def owner_context_identifier
    nil
  end

  # Returns true if owner context propagation is enabled.
  # Callers should check this before doing any resolution work
  # so that resolution queries are also gated behind the flag.
  sig { returns(T::Boolean) }
  def owner_context_propagation_enabled?
    GH::Context.enabled? &&
      FeatureFlag.vexi.enabled?(:owner_context_propagation, nil, default: false)
  end
end
