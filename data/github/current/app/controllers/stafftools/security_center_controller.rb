# typed: true
# frozen_string_literal: true

require "github/security_center/logging_helper"

module Stafftools
  class SecurityCenterController < StafftoolsController
    include GitHub::SecurityCenter::LoggingHelper

    DLQ = SecurityCenter::DeadLetterJob

    before_action :dotcom_required # limiting to dotcom so only GitHub staff can access

    def index
      render "stafftools/security_center/index", locals: {
        scheduled_jobs: scheduled_jobs
      }
    end

    # rubocop:todo GitHub/UseRestfulActions
    def run_dlq_job
      job_cache_key = params[:job_cache_key]
      job_cache_data = SecurityCenter::KV.store.get(job_cache_key).value { nil }

      unless job_cache_data.present?
        GitHub.logger.error(
          "Job cache not found.",
          "code.namespace": self.class.name,
          "code.function": __method__
        )
        return
      end

      job_to_run = DLQ::CacheData.from_json(job_cache_data)
      unless job_to_run.present?
        GitHub.logger.error(
          "Failed to parse cache data.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_center.dlq.cache_key": job_cache_data.key,
          "gh.security_center.dlq.cache_data": job_cache_data.data,
        )
        return
      end

      job_to_run.job_class.perform_later(**job_to_run.arguments)
      job_to_run.state = DLQ::CacheData::STATE_PERFORMED
      job_to_run.save!
      GitHub.logger.info(
        "Scheduled job performed manually.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_center.dlq.cache_key": job_to_run.key,
        "gh.security_center.dlq.cache_data": job_to_run.to_json,
      )
    rescue => e # rubocop:todo Lint/RescueException
      GitHub.logger.error(e)
      Failbot.report(e)
    ensure
      redirect_to stafftools_security_center_path
    end

    private

    sig { returns(T::Array[DLQ::CacheData]) }
    memoize def scheduled_jobs
      all_jobs = SecurityCenter::KV.store.mget_prefix(DLQ::CacheData::CACHE_PREFIX).value { {} }
      all_jobs.each_with_object([]) do |(key, data), scheduled_jobs|
        parsed_data = DLQ::CacheData.from_json(data)
        if parsed_data.nil?
          GitHub.logger.info(
            "Failed to parse cache data.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_center.dlq.cache_key": key,
            "gh.security_center.dlq.cache_data": data,
          )
        else
          scheduled_jobs << parsed_data unless parsed_data.performed?
        end
      end
    end

    sig { returns(T::Array[Integer]) }
    memoize def private_beta_business_ids
      FeatureFlag.vexi # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
        .actors_value_or_raise(:security_center_private_beta)
        .to_a
        .select { |v| v.include?("Business") }
        .map { |v| Integer(v.split(":")[1]) }
        .sort
    end

    sig { returns(T::Array[Integer]) }
    memoize def private_beta_org_ids
      FeatureFlag.vexi # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
        .actors_value_or_raise(:security_center_private_beta)
        .to_a
        .select { |v| v.include?("Organization") }
        .map { |v| Integer(v.split(":")[1]) }
        .sort
    end

    depends_on_clusters \
      ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      ApplicationRecord::SecurityOverviewAnalytics,
      only: [:index]

    depends_on_clusters \
      ApplicationRecord::Copilot,
      only: [:index],
      optional: true
  end
end
