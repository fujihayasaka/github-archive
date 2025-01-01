# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EarlyAccessMembershipOrderField < Platform::Enums::Base
      description "Properties by which early access membership connections can be ordered."
      visibility :internal

      value "CREATED_AT", "Order early access membership by creation time.", value: "created_at"
    end
  end
end
