# typed: strict
# frozen_string_literal: true

module Copilot
  module Metrics
    module Dashboards
      class Catalog
        extend T::Helpers
        include GitHub::Memoizer

        DashboardClasses = T.let(
          [
            Copilot::Metrics::Dashboards::UserOnboarding,
            Copilot::Metrics::Dashboards::CompletionsAcceptanceRate,
            Copilot::Metrics::Dashboards::GeneratedCodeAcceptanceRate,
            Copilot::Metrics::Dashboards::AverageCommits,
            Copilot::Metrics::Dashboards::AveragePullRequestsMerged,
            Copilot::Metrics::Dashboards::PullRequestLeadTime,
          ].freeze,
          T::Array[T.class_of(Copilot::Metrics::Dashboards::Base)],
        )

        sig { returns(::Organization) }
        attr_reader :owner

        sig { params(owner: ::Organization).void }
        def initialize(owner:)
          @owner = owner
        end

        sig { returns({ dashboards: T::Array[Copilot::Types::MetricsCatalogEntry] }) }
        def payload
          {
            dashboards: renderable_dashboards,
          }
        end

        private

        sig { returns(T::Array[Copilot::Types::MetricsCatalogEntry]) }
        def renderable_dashboards
          DashboardClasses.map do |klass|
            dashboard = klass.new(owner: owner)
            next unless dashboard.should_render?

            dashboard.catalog_entry
          end.compact
        end
      end
    end
  end
end
