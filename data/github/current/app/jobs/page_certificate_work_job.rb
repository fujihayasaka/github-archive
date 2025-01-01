# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class PageCertificateWorkJob < ApplicationJob
  queue_as :pages_https

  # certificate_id - The ID of the Page::Certificate we're doing work for.
  #
  # Returns nothing.
  def perform(certificate_id)
    report_attempts

    @certificate_id = certificate_id
    return if certificate.nil?

    state = certificate.current_state
    action = certificate.with_lock { with_write { do_work(state) } }

    case action
    when :proceed
      # If current state is approved and state machine says we can proceed, we are renewing an existing certificate
      # This tracks how far in advance we are renewing certificates to ensure we are not renewing too late
      if state == :approved && certificate.expires_at.present?
        GitHub.dogstats.distribution(
          "pages.certificates.days_before_expiration",
          certificate.days_before_expiration,
        )
      end
      schedule_work(certificate_id)
    when :retry, :error_retry
      schedule_retry(certificate_id)
    when :halt, :error_halt
      # do nothing
    else
      raise BadActionError, action
    end

    GitHub.dogstats.increment("pages.certificates.work", tags: [
      "state:#{state}",
      "action:#{action}",
    ])
  end

  # Process a certificate lifecycle event based on the specified state
  #
  # Returns a symbol signaling how the ApplicationJob should proceed.
  def do_work(state)
    case state
    when :new, :authorization_revoked, :bad_authz, :dns_changed, :private_key_revoked
      certificate.request_authorization
    when :authorization_created
      certificate.request_authorization_verification
    when :authorization_pending, :approved
      certificate.check_authorization_verification
    when :authorized
      certificate.request_certificate
    when :issued
      certificate.upload_certificate
    when :uploaded
      certificate.check_uploaded_certificate
    when :destroy_pending
      certificate.destroy_certificate
    else
      raise BadStateError, certificate.current_state
    end
  rescue Acme::Client::Error => err
    certificate.reset_flow
    track_error(err)
    :error_retry
  rescue *RECOVERABLE_ERRORS => err
    track_error(err)
    :error_retry
  rescue => err # rubocop:todo Lint/RescueException
    Failbot.report(err) unless err.is_a?(Page::Certificate::Error)
    track_error(err)
    :error_halt
  end

  # The certificate we're doing work for.
  #
  # Returns a Page::Certificate instance.
  def certificate
    return @certificate if defined?(@certificate)
    @certificate = Page::Certificate.find(@certificate_id)

    ensure_certificate_matches_page
  end

  # Schedule the next portion of work to be run.
  #
  # Returns nothing.
  def schedule_work(certificate_id)
    self.class.perform_later(certificate_id)
  end

  # Schedule the current portion of work to be retried.
  #
  # Returns nothing.
  def schedule_retry(certificate_id)
    raise TryLaterError, "Retry requested for certificate_id=#{certificate_id}"
  end

  # ApplicationJob Configuration
  #
  # ref: https://thehub.github.com/engineering/development-and-ops/dotcom/background-jobs/best-practices

  MAXIMUM_RETRIES = 5
  Error = Class.new(RuntimeError)
  TryLaterError = Class.new(Error) # Raise this when you want to retry the job.
  BadStateError = Class.new(Error)
  BadActionError = Class.new(Error)
  TooManyRetriesError = Class.new(Error)

  # Potentially transient errors that are retried
  RECOVERABLE_ERRORS = [
    TryLaterError,
    Fastly::Error,
    Faraday::Error,
    Page::Certificate::RecoverableError,
  ]

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on *T.unsafe(RECOVERABLE_ERRORS), wait: :polynomially_longer, attempts: MAXIMUM_RETRIES do |_job, _error|
    GitHub.logger.info("exceeded maximum retries: #{MAXIMUM_RETRIES}", {
      "code.namespace" => "pages-certificates-work-job"
    })
  end

  private

  def report_attempts
    GitHub.logger.info(
      "gh.pages.certificate.execution.retries" => executions,
      "code.namespace" => "pages-certificates-work-job"
    )
    GitHub.dogstats.distribution("pages.certificates.retries.dist", executions)
  end

  def track_error(err)
    return if certificate.nil?

    GitHub.logger.error({
      :exception => err,
      "gh.pages.certificate.id" => certificate.id,
      "gh.pages.certificate.state" => certificate.current_state,
      "gh.pages.fastly.certificate.id" => certificate.fastly_certificate_id,
      "gh.pages.authorization.url" => certificate.authorization_url,
      "gh.user.id" => certificate.repo&.owner_id,
      "gh.repo.id" => certificate.repo&.id,
      "code.namespace" => "pages-certificates-work-job",
      })

    GitHub.dogstats.increment("pages.certificates.error", tags: [
      "state:#{certificate.current_state}",
      "class:#{err.class.name.gsub(/::/, "_").downcase}",
    ])
  end

  def ensure_certificate_matches_page
    destroy_pending_if_no_matching_page if @certificate.present?
    @certificate
  end

  def destroy_pending_if_no_matching_page
    page = find_page_for_certificate
    @certificate.state = :destroy_pending unless page.present?
  end

  def find_page_for_certificate
    Page.select(:id).find_by(cname: [@certificate.domain, @certificate.alt_domain].compact)
  end
end
