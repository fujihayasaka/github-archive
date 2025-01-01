# typed: true
# frozen_string_literal: true

require "set"

class Repository::Availability
  DBStates = Set.new([:nonexist, :disabled, :dmca]).freeze
  GitStates = Set.new([
    :locked,
    :nonexistent, :empty,
    :down, :offline,
    :forking, :mirroring
  ]).freeze

  def initialize(repository)
    @repository = repository
    @db_state = @git_state = nil
  end

  # Public: Returns a Boolean for the current Repository DB and Git state.
  def ok?
    state == :ok
  end

  # Public: Returns a Boolean for the current Repository DB state.
  def db?
    db_state == :ok
  end

  # Public: Returns a Boolean for the current Repository Git state.
  def git?
    git_state == :ok
  end

  # Public: Returns a Symbol for the current Repository Git state.
  def git_state
    @git_state ||= check_git || :ok
  end

  # Public: Returns a Symbol for the current Repository DB state.
  def db_state
    @db_state ||= check_existence || :ok
  end

  # Public: Returns a Symbol for the current Repository DB and Git status.
  def state
    db? ? git_state : db_state
  end

  # Public: Sets the Repository DB state to a Symbol.  Empty values clear the
  # state, and invalid values set it to :ok.
  def db_state=(value)
    value = value.to_s
    value = value.strip unless value.size.zero?
    if value.size > 0
      value_sym = value.to_sym
      if DBStates.include?(value_sym)
        @db_state = value_sym
      else
        @db_state = :ok
      end
    else
      @db_state = nil
    end
  end

  # Public: Sets the Repository Git state to a Symbol.  Empty values clear the
  # state, and invalid values set it to :ok.
  def git_state=(value)
    value = value.to_s
    value = value.strip unless value.size.zero?
    if value.size > 0
      value_sym = value.to_sym
      if GitStates.include?(value_sym)
        @git_state = value_sym
      else
        @git_state = :ok
      end
    else
      @git_state = nil
    end
  end

  def inspect
    %(#<#{self.class} #{@repository.name_with_owner} == #{state}>)
  end

  def check_existence
    if !@repository || !@repository.active?
      :nonexist
    elsif @repository.disabled?
      :disabled
    elsif @repository.access.dmca?
      :dmca
    end
  end

  def check_git
    if !@repository
      :nonexist
    elsif @repository.locked?
      :locked
    elsif !@repository.exists_on_disk?
      :nonexistent
    elsif @repository.empty?
      if @repository.offline?
        if @repository.pushed_at
          :down
        else
          :offline
        end
      else # online but empty
        if @repository.parent_id?
          :forking
        elsif @repository.mirror?
          :mirroring
        else
          :empty
        end
      end
    elsif @repository.access.broken?
      :broken
    end
  end
end
