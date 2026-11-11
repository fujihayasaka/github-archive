# typed: strict
# frozen_string_literal: true

module Issues
  class UpdateOptions < T::Enum
    enums do
      Keep = new
      Delete = new
    end
  end
end
