# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable::Processor
  class Result < T::Enum
    enums do
      Success = new(:success)
      Error = new(:error)
      Skip = new(:skip)
    end
  end
end
