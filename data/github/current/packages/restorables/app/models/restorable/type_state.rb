# typed: false
# frozen_string_literal: true

# Internal: Belongs to a Restorable and keeps track of state for each restorable
# type. State transitions are all handled by the parent Restorable.
#
# See the Restorable documentation for usage details.
class Restorable
  class TypeState < ApplicationRecord::Domain::Restorables

    belongs_to :restorable

    validates_presence_of :restorable_id, :restorable_type, :state
    validates_uniqueness_of :restorable_id, scope: :restorable_type

    # No Restorable::TypeState is interpreted by Restorable as a saving state.
    # Every other state is represented by the state attribute.
    enum :state, {
      saved: 0,
      restoring: 1,
      restored: 2,
    }

    # One type per restorable type model. New restorable types may be added but
    # existing integer values must never be updated! The keys in this hash
    # should be named after the table name of the restorable type they represent.
    enum :restorable_type, {
      restorable_memberships: 0,
      restorable_repositories: 1,
      restorable_repository_stars: 2,
      restorable_watched_repositories: 3,
      restorable_issue_assignments: 4,
      restorable_custom_email_routings: 5,
    }

    def current_state
      state.to_sym
    end
  end
end
