# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class RepositoryAdvisorySerializer < BaseSerializer
      def scope
        RepositoryAdvisory.preload(:repository)
      end

      def as_json(options = {})
        hash = {
          url: url,
          repository: repository,
          ghsa_id: ghsa_id,
          cve_id: cve_id,
          state: state,
          summary: summary,
          author: author,
          created_at: created_at,
          private_vulnerability_report: private_vulnerability_report?,
          accepted: accepted?,
          description: description,
          affected_products: affected_products,
          severity: severity,
          cvss: cvss,
          cwes: cwes
        }

        hash
      end

      private

      def ghsa_id
        model.ghsa_id
      end

      def repository
        model.repository&.nwo
      end

      def state
        model.state
      end

      def cve_id
        model.cve_id
      end

      def summary
        model.title
      end

      def author
        model.author.login
      end

      def created_at
        time(model.created_at)
      end

      def private_vulnerability_report?
        model.external?
      end

      def accepted?
        model.accepted?
      end

      def description
        model.description
      end

      def severity
        model.severity
      end

      def affected_products
        model.affected_products.map do |affected_product|
          advisory_affected_product_hash(affected_product)
        end
      end

      def cvss
        advisory_cvss_hash(model)
      end

      def cwes
        model.cwes.map { |cwe| advisory_cwe_hash(cwe) }
      end

      def advisory_affected_product_hash(affected_product)
        {
          ecosystem: affected_product.ecosystem,
          package: affected_product.package,
          affected_versions: affected_product.affected_versions,
          patched_versions: affected_product.patches
        }
      end

      def advisory_cwe_hash(cwe)
        {
          cwe_id: cwe.cwe_id,
          name: cwe.name
        }
      end

      def advisory_cvss_hash(advisory)
        return nil unless advisory.cvss_v3.present?

        {
          vector_string: advisory.cvss_v3,
          score: advisory.cvss_v3_score
        }
      end
    end
  end
end
