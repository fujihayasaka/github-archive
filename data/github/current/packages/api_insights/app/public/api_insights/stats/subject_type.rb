# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  class SubjectType < T::Enum
    enums do
      User = new("user")
      Installation = new("installation")
    end
  end
end
