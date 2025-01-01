# typed: true
# frozen_string_literal: true

module Team::ParentChange
  CannotAcquireLockError = Class.new(Team::ParentChange::Error)
end
