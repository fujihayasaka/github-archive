# typed: false
# frozen_string_literal: true

# PageCertificateRemoveDuplicateJob deletes duplicate certificates
# If certificate has already been issued for a domain and user comes back and
# changes the cname to www variant of the already created certificate, we end
# up in a situation where we have two records in the Page::Certificate
#
# If we have two certificate objects each with domain and its www variant name
#       * delete the certificate object which is not tied to a page
#       * retrigger the certificate provisioning flow on the certificate which is in a bad state
class PageCertificateRemoveDuplicateJob < ApplicationJob
  queue_as :background_destroy

  # Fastly only accepts up to 1000 non-read requests per hour
  # Since this job will ultimately call DELETE on the Fastly API when
  # the record is destroyed, we limit it to 500 operations per hour
  SELECT_BATCH_SIZE = 500

  CertificateDuplicateDeletionError = Class.new(RuntimeError)

  def get_subdomain_alt_domain(domain)
    # Check if the domain is a subdomain domain(ex. "happy.example.com", "www.happy.example.com")
    if !GitHubPages::HealthCheck::Domain.new(domain).apex_domain?
      if domain.downcase.start_with?("www.")
        return alt_domain = domain.delete_prefix("www.")
      else
        return alt_domain = "www.#{domain}"
      end
    end
    ""
  end

  def perform(batch_size = SELECT_BATCH_SIZE)
    Failbot.push(app: "pages-certificates")

    deleted = 0
    Page::Certificate.throttle do
      GitHub.logger.info(
        "code.function" => "perform : begin",
        "code.namespace" => self.class.name)
      break if GitHub.enterprise?

      certs = ApplicationRecord::Domain::Repositories.connection.select_rows(Arel.sql(<<-SQL, batch_size: Arel.sql(batch_size.to_s)))
                  SELECT p_cert1.domain,p.cname FROM page_certificates p_cert1
                              INNER JOIN page_certificates p_cert2
                              ON p_cert1.domain = concat('www.', p_cert2.domain)
                              INNER JOIN pages p
                              ON p_cert1.domain = p.cname or p_cert2.domain = p.cname
                              LIMIT :batch_size
                  SQL

      break if certs.empty?
      GitHub.logger.info(
        "code.function" => "perform : search",
        "code.namespace" => self.class.name,
        "gh.pages.duplicate.certificate.count" => certs.size)
      GitHub.dogstats.gauge("pages.certificates.duplicate", certs.size)

      certs.each do |domain, page_cname|
        domain_certificate = Page::Certificate.find_by_domain(domain)
        alt_domain = domain_certificate&.get_alt_domain(domain)
        alt_domain = get_subdomain_alt_domain(domain) if alt_domain.blank?
        alt_domain_certificate = Page::Certificate.find_by_domain(alt_domain) unless alt_domain.blank?

        #If either of the certificate was not found there is no clean up needed
        if domain_certificate.nil? || alt_domain_certificate.nil?
          GitHub.logger.info(
            "code.function" => "perform : certificate object is nil",
            "code.namespace" => self.class.name,
            "gh.pages.domain" => domain_certificate&.domain,
            "gh.pages.alternate.domain" => alt_domain_certificate&.domain)
          next
        end

        # Destroying the record automatically calls out to Fastly
        # to delete the certificate through their Platform API
        case
        when page_cname == domain
          GitHub.logger.info(
            "code.function" => "perform :  destroy alt_domain certificate",
            "code.namespace" => self.class.name,
            "gh.pages.alternate.certificate.id" => alt_domain_certificate&.id,
            "gh.pages.alternate.domain" => alt_domain)
          if !GitHub.enterprise?
            with_write { alt_domain_certificate&.destroy_certificate }
            domain_certificate.resume_flow unless domain_certificate&.usable?
          end
        when page_cname == alt_domain
          GitHub.logger.info(
            "code.function" => "perform :  destroy domain certificate",
            "code.namespace" => self.class.name,
            "gh.pages.certificate.id" => domain_certificate&.id,
            "gh.pages.domain" => domain)
          if !GitHub.enterprise?
            with_write { domain_certificate&.destroy_certificate }
            alt_domain_certificate.resume_flow unless alt_domain_certificate&.usable?
          end
        end

        GitHub.dogstats.increment("pages.certificates.delete_duplicate", tags: ["state:success"])
        deleted += 1
      rescue Fastly::CertificateDeletionError => error
        # If the call to Fastly failed, we report it and move on
        # The next time the job runs, this certificate will be tried again automatically
        Failbot.report(
          CertificateDuplicateDeletionError.new(error), {
            "gh.pages.domain" => page_cname
            })
        GitHub.dogstats.increment("pages.certificates.delete_duplicate", tags: ["state:failure"])
      end
    end

    GitHub.dogstats.gauge("pages.certificates.duplicate.count", deleted)
  end

  retry_on_dirty_exit
end
