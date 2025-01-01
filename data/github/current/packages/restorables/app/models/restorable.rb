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
  has_many :issue_assignments
  has_many :repository_stars
  has_many :custom_email_routings

  # Internal: Are these restorable types all in a saving state?
  #
  # types - An array of Restorable::TypeState.restorable_types.keys
  #
  # Returns true or false.
  def saving?(types)
    count_type_states(types) < types.size
  end

  # Internal: Set the restorable type state to saved. Creates the type state
  # model to track state and fails quietly if the type state already exists.
  #
  # type - Symbol in Restorable::TypeState.restorable_types.keys
  #
  # Returns true or false.
  def saved(type)
    if type_state = type_states.create(restorable_type: type, state: :saved)
      type_state.persisted?
    else
      false
    end
  end

  # Internal: Are these restorable types all in a saved state?
  #
  # types - Each argument must be one of Restorable::TypeState.restorable_types.keys
  #
  # Returns true or false.
  def saved?(types)
    count_type_states(types, :saved) == types.size
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

  # Internal: Are these restorable types all in a restoring state?
  #
  # types - An array of Restorable::TypeState.restorable_types.keys
  #
  # Returns true or false.
  def restoring?(types)
    count_type_states(types, :restoring) == types.size
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
  #
  # Returns an Integer count of matching type states.
  def count_type_states(types, state = nil)
    if type_states.loaded?
      # If the association is already loaded, filter in memory to avoid additional database queries.
      types_set = Set.new(types)
      type_states.to_a.count do |type_state|
        types_set.include?(type_state.restorable_type.to_sym) &&
          (state.nil? || type_state.state.to_sym == state)
      end
    else
      # Fall back to database query
      type_states.where(type_state_attributes(types, state)).size
    end
  end

  def type_state_attributes(type, state = nil)
    type_integers = Array(type).map { |type| Restorable::TypeState.restorable_types[type] }

    { restorable_type: type_integers }.tap do |query_params|
      if state
        query_params[:state] = state
      end
    end
  end
end
