# typed: false
# frozen_string_literal: true

# Internal: This is a parent class that all other restorable models belong to.
# Restorable has many children that can be mixed and matched to handle different
# restorable scenarios.
#
# In addition to associations it defines the internal interface for checking and
# changing the state of a group of restorable records. State is saved in
# the type_states association, one record per restorable type.
#
# Usage:
#
#  > restorable = Restorable.create
#  > restorable.start_saving([:restorable_memberships, :restorable_repositories], remaining: 100)
# => true
#  > restorable.saving?([:issue_assignments, :memberships])
# => true
#  > restorable.saved(:memberships)
#  > restorable.saved?([:issue_assignments, :memberships])
# => false
#  > restorable.saved?([:memberships])
# => true
#
# This class should never be used as the public interface to restorables. Rather
# a model and public interface similar to Restorable::OrganizationUser should be
# created to support new scenarios.
class Restorable < ApplicationRecord::Domain::Restorables

  has_many :type_states
  has_many :memberships
  has_many :repositories
  has_many :watched_repositories
  has_many :custom_watched_repositories
  has_many :watched_repository_threads
  has_many :issue_assignments
  has_many :repository_stars
  has_many :custom_email_routings

  # Internal: Create TypeState records in :saving state for the given types with initial remaining count. This is
  # used when the saving process needs to be done with multiple, asynchronous iterations, so that we can accurately
  # know when to mark the restorable as saved.
  #
  # types - An array of Symbol representing TypeState states.
  # remaining - Integer representing the initial count for the :remaining column.
  #
  # Returns true if all TypeStates were created successfully, false otherwise.
  def start_saving(types, remaining:)
    types_array = Array(types)
    created_count = types_array.count do |type|
      type_states.create(
        restorable_type: type,
        state: :saving,
        remaining: remaining
      ).persisted?
    end

    # Reload the association if it's loaded to include new records
    type_states.reload if type_states.loaded?

    # Return true if we created records for all requested types
    created_count == types_array.size
  end

  # Internal: Atomically decrements the :remaining column for the given types by the specified amount,
  # with a minimum value of zero. If all affected types have :remaining values of zero after the update,
  # automatically calls .saved for those types.
  #
  # types - An array of Symbols or a single Symbol from Restorable::TypeState.restorable_types.keys
  # decrement_by - Integer amount to decrement by (default: 1)
  #
  # Returns true if all requested types were successfully processed, false otherwise.
  #
  # Example:
  #   restorable.report_saving_progress([:restorable_memberships, :restorable_repositories], 5)
  #   # => true
  def report_saving_progress(types, decrement_by = 1)
    types_array = Array(types)
    updated_count = type_states.where(type_state_attributes(types_array, :saving))
      .where("remaining > 0")
      .update_all(["remaining = GREATEST(remaining - ?, 0)", decrement_by.to_i])

    zeroed_types = type_states
      .where(type_state_attributes(types_array, :saving))
      .where(remaining: 0)
      .pluck(:restorable_type)
      .map(&:to_sym)
    saved_successfully = if zeroed_types.any?
      zeroed_types.all? { |type| saved(type) }
    else
      # Reload the association if it's loaded to reflect changes.
      # saved() handles this for the other branch.
      type_states.reload if type_states.loaded?

      true
    end

    updated_count == types_array.size && saved_successfully
  end

  # Internal: Are these restorable types all in a saving state?
  #
  # types - An array of Restorable::TypeState.restorable_types.keys
  #
  # Returns true or false.
  def saving?(types)
    # A type is in saving state if:
    # 1. No TypeState record exists for it, OR
    # 2. A TypeState record exists with state :saving
    # A type is NOT in saving state if it has any other state (:saved, :restoring, :restored)
    count_type_states(types, excluding: :saving) < types.size
  end

  # Internal: Set the restorable type state to saved. Creates the type state
  # model to track state or atomically updates an existing :saving state to :saved.
  #
  # type - Symbol in Restorable::TypeState.restorable_types.keys
  #
  # Returns true or false.
  def saved(type)
    # Attempt to create new TypeState record first (most common case)
    type_state = type_states.create(restorable_type: type, state: :saved)

    if type_state.persisted?
      true
    else
      # Creation failed, likely due to existing record. Atomically update existing :saving state.
      updated_count = type_states.where(type_state_attributes(type, :saving)).update_all(state: :saved)
      type_states.reload if type_states.loaded?
      updated_count > 0
    end
  end

  # Internal: Are these restorable types all in a saved state? Returns true when (1) all type_states are in the
  # :saved state or (2) at least one type_state is in the :saved state and all the rest are in the :restored state,
  # which can happen after a restore operation is cancelled after some type were already finished.
  #
  # types - Each argument must be one of Restorable::TypeState.restorable_types.keys
  #
  # Returns true or false.
  def saved?(types)
    saved_count = count_type_states(types, :saved)
    return true if saved_count == types.size

    # Check if we have a mix of :saved and :restored states
    if saved_count > 0
      restored_count = count_type_states(types, :restored)
      return saved_count + restored_count == types.size
    end

    false
  end

  # Internal: Find the restorable type state and update it's state to restoring.
  #
  # type - Symbol in Restorable::TypeState.restorable_types.keys
  #
  # Returns true or false.
  def restoring(type)
    type_state = type_states.where(type_state_attributes(type, :saved)).first

    if type_state.present?
      type_state.update_attribute(:state, :restoring)
    else
      false
    end
  end

  # Internal: Are these restorable types currently being restored?
  #
  # types - An array of Restorable::TypeState.restorable_types.keys
  #
  # Returns true or false.
  def restoring?(types)
    count_type_states(types, :restoring) > 0
  end

  # Internal: Find the restorable type state and update it's state to restored.
  #
  # type - Symbol in Restorable::TypeState.restorable_types.keys
  #
  # Returns true or false.
  def restored(type)
    type_state = type_states.where(type_state_attributes(type, :restoring)).first

    if type_state.present?
      type_state.update_attribute(:state, :restored)
    else
      false
    end
  end

  # Internal: Are these restorable types all in a restored state?
  #
  # *types - Each argument must be one of Restorable::TypeState.restorable_types.keys
  #
  # Returns true or false.
  def restored?(types)
    count_type_states(types, :restored) == types.size
  end

  private

  # Internal: Count the number of type states that match the given types and state.
  #
  # types - An array of Restorable::TypeState.restorable_types.keys
  # state - Optional Symbol representing the state to filter by
  # excluding - Optional Symbol or Array of Symbols representing states to exclude from the count
  #
  # Returns an Integer count of matching type states.
  def count_type_states(types, state = nil, excluding: nil)
    if type_states.loaded?
      # If the association is already loaded, filter in memory to avoid additional database queries.
      types_set = Set.new(types)
      excluded_states = Array(excluding).map(&:to_sym) if excluding.present?
      type_states.to_a.count do |type_state|
        type_matches = types_set.include?(type_state.restorable_type.to_sym)
        state_matches = state.nil? || type_state.state.to_sym == state
        not_excluded = excluding.blank? || !excluded_states.include?(type_state.state.to_sym)

        type_matches && state_matches && not_excluded
      end
    else
      # Fall back to database query
      query = type_states.where(type_state_attributes(types, state))
      if excluding.present?
        query = query.where.not(type_state_attributes(types, excluding))
      end
      query.size
    end
  end

  def type_state_attributes(type, state = nil)
    type_integers = Array(type).map { |type| Restorable::TypeState.restorable_types[type] }

    { restorable_type: type_integers }.tap do |query_params|
      query_params[:state] = state if !state.nil?
    end
  end
end
