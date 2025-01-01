# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  class SourceType < T::Enum
    enums do
      Enterprise = new
      Organization = new
    end
  end
end
