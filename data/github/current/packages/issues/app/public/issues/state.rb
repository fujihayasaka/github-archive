# typed: strict
# frozen_string_literal: true

module Issues
  class State < T::Enum
    enums do
      Open = new
      Closed = new
    end
  end
end
