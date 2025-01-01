# typed: false
# frozen_string_literal: true

module ExploreFeed
  module ValidationHelpers
    def valid?
      missing_attributes = self.class::REQUIRED_ATTRIBUTES.select { |attr| attributes[attr].nil? }

      if missing_attributes.present?
        raise ExploreFeedError, "Missing required attributes: #{missing_attributes.join(", ")}"
      else
        true
      end
    rescue ExploreFeedError => e
      Failbot.report(e, app: "github", type: self.class.name, attributes: attributes)
      false
    end
  end
end
