# typed: true
# frozen_string_literal: true

class Permission
  class Action < T::Enum
    include Comparable

    enums do
      Read  = new(Permission.actions[:read])
      Write = new(Permission.actions[:write])
      Admin = new(Permission.actions[:admin])
    end

    sig { params(value: T.any(String, Symbol, Integer)).returns(Action) }
    def self.from(value)
      return deserialize(value) if value.is_a?(Integer)

      deserialize(T.must(Permission.actions[value]))
    end

    def <=>(other)
      self.serialize <=> other.try(:serialize)
    end

    def to_sym
      self.to_s.to_sym
    end

    def to_s
      T.must(Permission.actions.key(self.serialize))
    end

    sig { returns(T::Array[Action]) }
    def expand
      value = self.serialize
      expanded = []

      while (found_action = Permission.actions.key(value))
        expanded << self.class.from(found_action)
        value -= 1
      end

      expanded
    end
  end
end
