# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PlanFeaturePrivacy < Platform::Enums::Base
      visibility :internal

      description "The privacy of a plan feature."

      value "PUBLIC", "Public", value: :public
      value "PRIVATE", "Private", value: :private
    end
  end
end
