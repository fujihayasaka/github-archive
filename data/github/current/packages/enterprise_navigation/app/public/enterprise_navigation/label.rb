# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  class Label < T::Enum
    enums do
      NEW = new              # new
      PRIVATE_PREVIEW = new  # alpha
      PREVIEW = new          # beta
      PUBLIC = new           # no label
    end
  end
end
