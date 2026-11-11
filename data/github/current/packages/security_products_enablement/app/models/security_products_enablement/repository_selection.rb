# typed: strict
# frozen_string_literal: true

# Represents the repositories selection for a security product configuration
class SecurityProductsEnablement::RepositorySelection

  # Maximum number of repository IDs that can be specified in Quick Setup configuration operations
  # (create, update, and replace actions)
  MAX_REPOSITORY_IDS_FOR_QUICK_SETUP = 500

  sig { returns(Value) }
  attr_accessor :value

  class Value < T::Enum
    enums do
      All = new("all")
      None = new("none")
      Selected = new("selected")
      NotApplicable = new("not_applicable")
    end
  end

  sig { params(value: Value, repository_ids: T.nilable(T::Array[Integer])).void }
  def initialize(value, repository_ids = [])
    @value = T.let(value, Value)
    @repository_ids = T.let(repository_ids, T.nilable(T::Array[Integer]))
    if value == Value::Selected
      if @repository_ids.nil? || @repository_ids.empty?
        raise ArgumentError, "repository_ids must be provided when value is 'selected'"
      end
    elsif @repository_ids&.any?
      raise ArgumentError, "repository_ids must be omitted unless value is 'selected'"
    end
  end

  sig { returns(SecurityProductsEnablement::RepositorySelection) }
  def self.all
    new(Value::All)
  end

  sig { returns(SecurityProductsEnablement::RepositorySelection) }
  def self.none
    new(Value::None)
  end

  sig { returns(SecurityProductsEnablement::RepositorySelection) }
  def self.not_applicable
    new(Value::NotApplicable)
  end

  sig { params(repository_ids: T::Array[Integer]).returns(SecurityProductsEnablement::RepositorySelection) }
  def self.selected(repository_ids)
    new(Value::Selected, repository_ids)
  end

  sig { returns(T::Array[Integer]) }
  def selected_repository_ids
    @repository_ids || []
  end

  sig { returns(T::Boolean) }
  def all?
    value == Value::All
  end

  sig { returns(T::Boolean) }
  def none?
    value == Value::None
  end

  sig { returns(T::Boolean) }
  def selected?
    value == Value::Selected
  end

  sig { returns(T::Boolean) }
  def not_applicable?
    value == Value::NotApplicable
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
    return false unless other.is_a?(SecurityProductsEnablement::RepositorySelection)
    return false unless value == other.value

    if selected?
      selected_repository_ids.sort == other.selected_repository_ids.sort
    else
      true
    end
  end
end
