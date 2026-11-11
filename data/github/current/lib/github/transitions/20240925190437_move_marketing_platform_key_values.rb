# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MoveMarketingPlatformKeyValues < MoveKeyValuesBase
      class MarketingPlatformKeyValues < ApplicationRecord::Domain::Site
        self.table_name = :marketing_platform_key_values
      end

      sig { override.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class
        MarketingPlatformKeyValues
      end

      iterate_key_values [
        "site.swp.customer\\_stories.category.%.staff:%",
        "site.swp.customer\\_stories.story.%.staff:%",
        "site.contentful.customer\\_stories.pages.index.for\\_staff:%",
        "site.contentful.customer\\_stories.pages.index.v2.for\\_staff:%",
        "site.swp.customer\\_stories.index.staff:%",
        "site.swp.events.%",
        "site.swp.landing\\_pages.%",
        "site.contentful.marketing.newsroom.pages.%.%/v1",
        "site.swp.open\\_source.index",
        "site.swp.resources.%",
        "site.contentful.marketing.sitemap/v2",
        "site.contentful.marketing.solutions.pages.%.%/v2",
        "site.swp.startups.partners",
        "site.swp.readme.index.staff:%",
        "site.swp.readme.rss",
        "site.swp.readme.developer\\_stories.%.staff:%",
        "site.swp.readme.featured\\_articles.%.staff:%",
        "site.swp.readme.guides.%.staff:%",
        "site.swp.readme.podcasts.%.staff:%",
        "site.swp.readme.topics.%.staff:%",
      ]
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: %w(cleanup))

  GitHub::Transitions::MoveMarketingPlatformKeyValues.new(args).run
end
