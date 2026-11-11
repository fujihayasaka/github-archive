# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PinnedDiscussionGradient < Platform::Enums::Base
      description "Preconfigured gradients that may be used to style discussions pinned within a repository."

      DiscussionSpotlight::NEXT_GRADIENT_NAMES.each do |gradient_name|
        value gradient_name.upcase, "A gradient of #{gradient_name.to_s.gsub /_/, ' to '}", value: gradient_name
      end
    end
  end
end
