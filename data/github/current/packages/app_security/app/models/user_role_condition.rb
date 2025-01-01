# typed: strict
# frozen_string_literal: true

class UserRoleCondition < T::Struct
  class Target < T::Enum
    enums do
      AllOrgs = new("all_orgs")
      SomeOrgs = new("some_orgs")
    end
  end

  prop :version, Integer, default: 1

  prop :target, Target
  prop :target_ids, T.nilable(T::Array[Integer])
end
