# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# PageCertificateRemoveExpiredJob deletes certificates for
# all pages sites that expired over 30 days ago
class PageCertificateRemoveExpiredJob < ApplicationJob
  queue_as :background_destroy

  # Fastly only accepts up to 1000 non-read requests per hour
  # Since this job will ultimately call DELETE on the Fastly API when
  # the record is destroyed, we limit it to 100 operations per hour
  SELECT_BATCH_SIZE = 100

  CertificateDeletionError = Class.new(RuntimeError)

  def perform(expiration_date = Time.current.utc - 30.days)
    Failbot.push(app: "pages-certificates")

    deleted = 0

    Page::Certificate.throttle do
      GitHub::Logger.log(
        "code.namespace" => self.class.name,
        "code.function" => "begin",
        "gh.pages.certificate.expiration_date" => expiration_date)
      break if GitHub.enterprise?

      certs = Page::Certificate
        .where("expires_at < ?", expiration_date)
        .order(id: :asc)
        .limit(SELECT_BATCH_SIZE)
        .pluck(:id, :domain)

      GitHub::Logger.log(
        "code.namespace" => self.class.name,
        "code.function" => "search",
        "gh.pages.certificate.expiration_date" => expiration_date,
        "gh.pages.certificate.count" => certs.size
      )

      break if certs.empty?

      certs.each do |id, domain|
        # Destroying the record automatically calls out to Fastly
        # to delete the certificate through their Platform API
        with_write { Page::Certificate.destroy(id) }
        GitHub.dogstats.increment("pages.certificates.delete", tags: ["state:success"])
        deleted += 1
        GitHub::Logger.log(
          "code.namespace" => self.class.name,
          "code.function" => "delete",
          "gh.pages.certificate.expiration_date" => expiration_date,
          "gh.pages.certificate.domain" => domain
        )
      rescue Fastly::CertificateDeletionError => error
        # If the call to Fastly failed, we report it and move on
        # The next time the job runs, this certificate will be tried again automatically
        Failbot.report(
          CertificateDeletionError.new(error), {
          "gh.pages.certificate.id" => id,
          "gh.pages.domain" => domain,
        })
        GitHub.dogstats.increment("pages.certificates.delete", tags: ["state:failure"])
      end
    end

    GitHub::Logger.log(
      "code.namespace" => self.class.name,
      "code.function" => "finish",
      "gh.pages.certificate.expiration_date" => expiration_date,
      "gh.pages.certificate.deleted.count" => deleted
    )
  end

  retry_on_dirty_exit
end
