# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class PageCertificateCreateJob < ApplicationJob
  queue_as :pages_https

  retry_on_recoverable_exceptions

  def perform(page)
    return unless page.cname

    GitHub.logger.with_named_tags(
      "gh.user.id": page.repository&.owner_id,
      "gh.repo.id": page.repository_id,
      "gh.pages.cname": page.cname,
      "code.namespace": "page-certificate-create-job",
    ) do
      with_write do
        page.create_cname_certificate
        # Rerun pre-validation callbacks, which may depend on having a certificate present, then save any changes they make
        page.reload.valid?
        page.save if page.changes.present?
      end
    end
  end
end
