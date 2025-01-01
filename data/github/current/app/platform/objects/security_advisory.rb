# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SecurityAdvisory < Platform::Objects::Base
      visibility :public

      description "A GitHub Security Advisory"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, security_advisory)
        return false if security_advisory.unreviewed?

        security_advisory.async_readable_by?(permission.viewer)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, security_advisory)
        return false if security_advisory.unreviewed?

        security_advisory.async_readable_by?(permission.viewer)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [[:gsa, :ghsa_id, :id]], as: "GSA", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |security_advisory|
        {
          prefix: :gsa,
          ghsa_id: security_advisory.ghsa_id,
          id: security_advisory.id
        }
      end

      database_id_field
      field :ghsa_id, String, "The GitHub Security Advisory ID", null: false
      field :summary, String, "A short plaintext summary of the advisory", null: false
      field :description, String, "This is a long plaintext description of the advisory", null: false
      field :severity, Enums::SecurityAdvisorySeverity, "The severity of the advisory", null: false
      field :permalink, Scalars::URI, "The permalink for the advisory", null: true
      field :credits, "Credits associated with this Advisory", resolver: Resolvers::SecurityAdvisoryCredits, null: false
      field :classification, Enums::SecurityAdvisoryClassification, "The classification of the advisory", null: false

      field :identifiers, [SecurityAdvisoryIdentifier], "A list of identifiers for this advisory", null: false
      field :references, [SecurityAdvisoryReference], "A list of references for this advisory", null: false
      field :published_at, Scalars::DateTime, "When the advisory was published", null: false
      field :updated_at, Scalars::DateTime, "When the advisory was last updated", null: false
      field :withdrawn_at, Scalars::DateTime, "When the advisory was withdrawn, if it has been withdrawn", null: true

      # the reason for using a String instead of an Enum for origin is to avoid leaking details about who we are planning to get advisories from before we are ready
      field :origin, String, "The organization that originated the advisory", null: false

      field :vulnerabilities, "Vulnerabilities associated with this Advisory",
                              resolver: Resolvers::SecurityVulnerabilities,
                              null: false
      field :cvss, Objects::CVSS, "The CVSS associated with this advisory", null: false

      def cvss
        {
          vector_string: @object.cvss_v3,
          score: @object.cvss_v3_score
        }
      end

      field :cvss_severities, Objects::CvssSeverities, "The CVSS associated with this advisory", null: false, feature_flag: :advisory_db_cvss_v4

      def cvss_severities
        {
          cvss_v3: { vector_string: @object.cvss_v3, score: @object.cvss_v3_score },
          cvss_v4: { vector_string: @object.cvss_v4, score: @object.cvss_v4_score },
        }
      end

      field :cwes, Connections.define(Objects::CWE), "CWEs associated with this Advisory", null: false

      field :notifications_permalink, Scalars::URI, "The permalink for the advisory's dependabot alerts page", null: true

      def self.load_from_next_global_id(parsed_id)
        prefix = parsed_id.parts[:prefix]
        unless prefix == :gsa
          raise(Platform::Errors::NotFound, "Template prefix '#{prefix}' does not match an existing global id template")
        end
        ghsa_id = parsed_id.parts[:ghsa_id]
        Loaders::ActiveRecord.load(T.cast(::SecurityAdvisory.disclosed, ActiveRecord::Relation), ghsa_id, column: :ghsa_id)
      end

      def self.load_from_global_id(ghsa_id)
        Loaders::ActiveRecord.load(T.cast(::SecurityAdvisory.disclosed, ActiveRecord::Relation), ghsa_id, column: :ghsa_id)
      end
    end
  end
end
