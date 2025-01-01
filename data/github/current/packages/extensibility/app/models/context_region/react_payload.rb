# typed: true
# frozen_string_literal: true

module ContextRegion
  class ReactPayload
    def self.generate(crumb:)
      {
        crumbs: crumb.crumbs.map(&:to_h)
      }
    end
  end
end
