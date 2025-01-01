# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  class Label < T::Enum
    enums do
      PRIVATE_PREVIEW = new  # alpha
      PREVIEW = new          # beta
      PUBLIC = new           # no label
    end
  end
end
