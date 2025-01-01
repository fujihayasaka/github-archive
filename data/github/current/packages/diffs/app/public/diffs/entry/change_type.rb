# typed: strict
# frozen_string_literal: true

module Diffs::Entry
  # See GitHub::Diff::Entry::LABELS
  class ChangeType < T::Enum
    enums do
      Added = new("ADDED")
      Changed = new("CHANGED")
      Copied = new("COPIED")
      # "DELETED" does not appear in GitHub::Diff::Entry::LABELS, but it does appear on the client side
      # in ui/packages/diff-file-helpers/diff-file-helpers PatchStatus, so we're including it here.
      Deleted = new("DELETED")
      Empty = new("EMPTY")
      Modified = new("MODIFIED")
      Removed = new("REMOVED")
      Renamed = new("RENAMED")
      # We sometimes need to inject an unchanged file into a diff, e.g.
      # because it has annotations.
      Unchanged = new("UNCHANGED")
    end
  end
end
