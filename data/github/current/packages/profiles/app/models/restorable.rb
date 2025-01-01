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
#  > restorable.saving?(:issue_assignments, :memberships)
# => true
#  > restorable.saved(:memberships)
#  > restorable.saved?(:issue_assignments, :memberships)
# => false
#  > restorable.saved?(:memberships)
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
  # *types - Each argument must be one of Restorable::TypeState.restorable_types.keys
  #
  # Returns true or false.
  def saving?(*types)
    type_states.where(type_state_attributes(types)).count < types.size
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
  # *types - Each argument must be one of Restorable::TypeState.restorable_types.keys
  #
  # Returns true or false.
  def saved?(*types)
    type_states.where(type_state_attributes(types, :saved)).count == types.size
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
  # *types - Each argument must be one of Restorable::TypeState.restorable_types.keys
  #
  # Returns true or false.
  def restoring?(*types)
    type_states.where(type_state_attributes(types, :restoring)).count == types.size
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
  def restored?(*types)
    type_states.where(type_state_attributes(types, :restored)).count == types.size
  end

  private

  def type_state_attributes(type, state = nil)
    type_integers = Array(type).map { |type| Restorable::TypeState.restorable_types[type] }

    { restorable_type: type_integers }.tap do |query_params|
      if state
        query_params[:state] = state
      end
    end
  end
end
