# typed: strict
# frozen_string_literal: true

# Functionality for accounts that can have StaffNotes.
# Included by User (and therefore Organization), and Business.
module StaffNotesDependency
  extend ActiveSupport::Concern

  # Public: Does the account have a recent StaffNote?
  #
  # since - Time representing the period to consider "recent". Defaults to two years.
  #
  # Returns Boolean.
  sig { params(since: T.nilable(Time)).returns(T::Boolean) }
  def recent_staff_note?(since = 2.years.ago)
    return false if T.unsafe(self).staff_notes.empty?
    T.unsafe(self).staff_notes.last.created_at > since
  end

  # Public: Does the account have a pinned StaffNote?
  #
  # Returns Boolean.
  sig { returns(T::Boolean) }
  def pinned_staff_note?
    scope = T.unsafe(self).staff_notes.pinned
    github = ::User.find_by login: "github"
    scope = scope.where.not(user: github) if github
    scope.any?
  end
end
