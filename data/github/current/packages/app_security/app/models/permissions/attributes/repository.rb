# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class Repository < Default

      def subject_attributes
        super.merge(participant.async_subject_attributes.sync)
      end
    end
  end
end
