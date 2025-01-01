# typed: true
# frozen_string_literal: true

class Permission
  class ActionString < T::Enum
    extend T::Sig
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
  end
end
