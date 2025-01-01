# typed: true
# frozen_string_literal: true

class ImportResult
  attr_reader :errors

  def initialize(changesets, errors = [])
    @changesets = changesets
    @errors = errors
  end

  def new_changesets
    @changesets.select(&:new?)
  end

  def updated_changesets
    @changesets.select(&:changed?) - deleted_changesets
  end

  def deleted_changesets
    @changesets.select(&:deleted?)
  end

  def new_count
    new_changesets.size
  end

  def updated_count
    updated_changesets.size
  end

  def deleted_count
    deleted_changesets.size
  end

  def any_new?
    new_count > 0
  end

  def any_updates?
    updated_count > 0
  end

  def any_deletes?
    deleted_count > 0
  end

  def any_changes?
    any_new? || any_updates? || any_deletes?
  end
end
