# typed: strict
# frozen_string_literal: true

module AzureEXP::Beta
  class AssignmentState < T::Enum
    enums do
      None = new
      Local = new
      Remote = new
    end
  end
end
