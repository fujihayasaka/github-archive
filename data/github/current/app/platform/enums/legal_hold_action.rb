# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class LegalHoldAction < Platform::Enums::Base
      description "The legal hold action to perform on accounts."

      visibility :internal

      value "PLACE", "Place legal hold on the account to prevent repository purging."
      value "CLEAR", "Clear legal hold from the account."
    end
  end
end
