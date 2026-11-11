# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class SponsorsCriterionBySlug < Platform::Loader
      def self.load(slug:)
        self.for.load(slug)
      end

      def fetch(slugs)
        GitHub.dogstats.distribution_time("sponsors_criterion.lookup_by_slug.time") do
          ::SponsorsCriterion.where(slug: slugs).index_by(&:slug)
        end
      end
    end
  end
end
