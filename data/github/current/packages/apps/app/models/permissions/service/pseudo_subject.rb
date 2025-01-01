# typed: true
# frozen_string_literal: true

module Permissions
  class Service
    class PseudoSubject < T::Struct
      prop :ability_id, Integer
      prop :ability_type, String
    end
  end
end
