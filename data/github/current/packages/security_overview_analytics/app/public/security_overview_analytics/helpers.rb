# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Helpers
    extend T::Helpers

    abstract!

    sig { returns(T.class_of(CalendarPopulationJob)) }
    def self.calendar_population_job_class
      CalendarPopulationJob
    end

    sig { returns(T::Array[T.class_of(ApplicationJob)]) }
    def self.abstract_job_classes
      [
        Initialization::TenantBaseJob,
        Initialization::Repositories::BaseJob,
        Initialization::Repositories::BaseBatchedJob,
        Backfill::FanoutBaseJob,
        Fanout::TenantBaseJob,
        Fanout::RepositoryBaseJob
      ]
    end

    sig { returns(T.class_of(Initialization::BusinessJob)) }
    def self.initialization_business_job_class
      Initialization::BusinessJob
    end

    sig { returns(T.class_of(Initialization::OrganizationJob)) }
    def self.initialization_organization_job_class
      Initialization::OrganizationJob
    end
  end
end
