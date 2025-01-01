# typed: true
# frozen_string_literal: true

module Billing
  module Platform
    module Api
      class RepoUsageLineItem
        include AvatarHelper

        def initialize(raw_usage_line_item, org, repo)
          @raw_usage_line_item = raw_usage_line_item.with_indifferent_access
          @org = org
          @repo = repo
        end

        def to_json
          {
            # use the grossAmount if the billedAmount is not present since some
            # Billing Platform endpoints (like net_usage) send grossAmount while others
            # send billedAmount
            billedAmount: raw_usage_line_item[:billedAmount].nil? ? raw_usage_line_item[:grossAmount] : raw_usage_line_item[:billedAmount],
            quantity: raw_usage_line_item[:quantity],
            product: raw_usage_line_item[:product],
            repo: {
              name: @repo.present? ? @repo.name : "Deleted Repository",
            },
            org: {
              name: @org.present? ? @org.safe_profile_name : "Deleted Organization",
              # We want to get URL for 16x16 avatar since this is what is shown in the usage table
              avatarSrc: @org.present? ? avatar_url_for(@org, 16) : "",
            },
            usageAt: Time.at(0, raw_usage_line_item[:usageAt], :millisecond).utc,
          }
        end

        private

        attr_reader :raw_usage_line_item
      end
    end
  end
end
