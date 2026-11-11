# typed: true
# frozen_string_literal: true

class InstallAutomaticIntegrationsJob < ApplicationJob
  class Result
    # action: one of "installed" or "repositories_added"
    def self.success(job, action, installation, repositories, options = {})
      job_status = create_job_status(job, :success)
      result = new(job_status, installation: installation, repositories: repositories)
      result.report(job, action, installation.target, installation.integration, options)
      result
    end

    def self.failed(job, reason, target, integration, options = {})
      job_status = create_job_status(job, :error)
      result = new(job_status, reason: reason, exception: options[:exception])
      result.report(job, reason, target, integration, options)
      result
    end

    def self.already_installed(job, status, installation, options = {})
      job_status = create_job_status(job, :success)
      result = new(job_status, installation: installation, already_installed: true)
      result.report(job, status, installation.target, installation.integration, options)
      result
    end

    def self.create_job_status(job, status)
      id = InstallAutomaticIntegrationsJob.job_id(job)
      Apps::JobStatus.new(id:, state: status.to_s)
    end

    attr_reader :installation, :repositories, :job_status, :reason, :exception

    def initialize(job_status, installation: nil, repositories: nil, reason: nil, exception: nil, already_installed: false)
      # Note: consider persisting JobStatus if/when we start persisting Result
      @job_status        = job_status
      @installation      = installation
      @repositories      = repositories
      @reason            = reason
      @exception         = exception
      @already_installed = already_installed
    end

    delegate :success?, :error?, to: :job_status
    alias :failed? :error?

    def already_installed?
      !!@already_installed
    end

    def report(job, status, target, integration, options = {})
      return unless job_status.present?

      log_options = {}
      if options[:enqueued_timestamp].present?
        log_options["gh.job.enqueued_timestamp"] = options[:enqueued_timestamp]
      end

      tags = options.fetch(:tags, [])
      if options[:reason].present?
        tags << "reason:#{options[:reason]}"
        log_options["gh.job.reason"] = options[:reason]
      end

      if options[:installation_type].present?
        tags << "installation_type:#{options[:installation_type]}"
        log_options["gh.installation.type"] = options[:installation_type]
      end

      tags.concat(["installation_queue:#{job.queue_name}", "integration:#{integration.slug}", "owner:#{integration.owner.display_login}"])
      GitHub.dogstats.increment("jobs.install_automatic_integrations.#{status}", tags: tags.flatten)

      if options[:exception].present?
        log_options["gh.job.exception_message"] = options[:exception].to_s
      end

      # InstallAutomaticIntegrationsJob -> InstallAutomaticIntegrations
      # This is to avoid migration issues https://github.com/github/ecosystem-apps/issues/1037.
      job_name = job.class.name.gsub(/Job\z/, "")

      GitHub.logger.info(
        {
          "gh.job.name" => job_name,
          "gh.job.status" => status.to_s,
          "gh.job.installation_queue" => job.queue_name,
          "gh.integration.id" => integration.id,
          "gh.integration.owner.id" => integration.owner.id,
          "gh.installation.target.id" => target&.id,
        }.merge(log_options),
      )
    end
  end
end
