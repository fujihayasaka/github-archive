# typed: true
# frozen_string_literal: true

class Permission
  class Action < T::Enum
    extend T::Sig
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
      self.serialize <=> other.serialize
    end

    def to_sym
      T.must(Permission.actions.key(self.serialize)).to_sym
    end
  end
end
