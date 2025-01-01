# typed: true
# frozen_string_literal: true

class Permission
  class ActionString < T::Enum
    include Comparable

    enums do
      Read  = new("read")
      Write = new("write")
      Admin = new("admin")
    end

    def <=>(other)
      self.to_i <=> other.to_i
    end

    def to_i
      Permission.actions[self.serialize]
    end

    sig { returns(T::Array[ActionString]) }
    def expand
      value = self.to_i
      expanded = []

      while (found_action = Permission.actions.key(value))
        expanded << self.class.deserialize(found_action)
        value -= 1
      end

      expanded
    end
  end
end
