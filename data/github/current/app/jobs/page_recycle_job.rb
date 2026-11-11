# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class PageRecycleJob < ApplicationJob
  # This job is a background maintenance task that works across a stamp.
  exempt_from_tenant_context_requirement

  queue_as :background_destroy

  class PageRecycleError < StandardError; end

  retry_on PageRecycleError, OpenSSL::SSL::SSLErrorWaitReadable, wait: 5.seconds, attempts: 3 do |_job, error|
    Failbot.report(error, app: "pages")
    GitHub.dogstats.increment("pages.page.recycle", tags: ["state:failure"])
  end

  sig { params(hostnames: T::Array[String], storage_path: String, page_id: T.nilable(Numeric), start_time: T.nilable(Time), delegate: T.untyped).void }
  def perform(hostnames, storage_path, page_id = nil, start_time = nil, delegate = GitHub::Pages::Management::Delegate.new(logger: GitHub::Logger))
    # Since this job is delayed and can be retried later on, do a safety
    # check first to make sure we're not about to delete a replica that was
    # created after this job was queued.
    if start_time.present?
      replicas = Page::Replica.where(page_id: page_id)
      hostnames = hostnames.reject do |host|
        replica = replicas.find { |r| r.host == host && T.must(r.created_at) > start_time }
        !replica.nil?
      end
    end
    command = GitHub::Pages::Management::DeletePathFromHostsDisk.new(
      hosts: hostnames,
      path: storage_path,
      delegate: delegate
    )
    raise PageRecycleError.new("ssh clean failed, check splunk log for more detail.") unless command.perform
    GitHub.dogstats.increment("pages.page.recycle", tags: ["state:succeed"])

    # Outside of GHES/Proxima, purge the CDN
    if !GitHub.enterprise? && !GitHub.multi_tenant_enterprise?
      begin
        GitHub.dogstats.increment("pages.cdn.purge", tags: ["state:succeed"]) if Page.where(id: page_id).first&.purge_cdn
      rescue Fastly::CDNPurgeError, Fastly::ValidationError => error
        GitHub.dogstats.increment("pages.cdn.purge", tags: ["state:failure"])
      end if page_id.present?
    end

  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
end
