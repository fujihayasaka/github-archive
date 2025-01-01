# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class MarketplaceListing < Default
      def subject_attributes
        super.merge(
          "subject.owner.id" => participant.owner.id,
          "subject.business.id" => participant.owner&.async_business&.sync&.id,
        )
      end
    end
  end
end
