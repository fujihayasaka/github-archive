# typed: strict
# frozen_string_literal: true

class Integration
  class Permissions
    class RepositorySelection < T::Enum
      enums do
        All = new
        Any = new
        Subset = new
      end
    end
  end
end
