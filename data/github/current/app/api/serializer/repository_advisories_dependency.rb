# typed: true
# frozen_string_literal: true

module Api::Serializer::RepositoryAdvisoriesDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::OrganizationsDependency }
  requires_ancestor { Api::Serializer::RepositoriesDependency }
  requires_ancestor { Api::Serializer::UserDependency }

  def advisory_credits_hash(credits, options = {})
    # Credits aren't applicable in GHES/Proxima since they're only for public advisories
    return [] if GitHub.single_or_multi_tenant_enterprise?
    return [] unless credits

    credits.map do |credit|
      advisory_credit_hash(credit, options)
    end
  end

  def advisory_credit_hash(credit, options = {})
    return nil unless credit

    payload = {
      user: simple_user_hash(credit.recipient, options),
      type: credit.credit_type,
      state: credit.state,
    }

    payload
  end

  def private_vulnerability_reporting_hash(repository, options)
    { enabled: repository.private_vulnerability_reporting_enabled? }
  end

  def repository_advisories_hash(data, options)
    advisories = data.fetch(:advisories, [])

    associations = T.let(
      [
        :affected_products,
        :author,
        { credits: :recipient },
        :cwes,
        :publisher,
        { workspace_repository: :owner },
      ],
      T::Array[T.any(Symbol, T::Hash[Symbol, Symbol])]
    )
    associations << { repository: :owner } if FeatureFlag.vexi.enabled?(:repo_advisories_api_prefill_repo_owner, default: false)

    GitHub::PrefillAssociations.prefill_associations(advisories, associations)

    advisory_to_writable_by_hash = {}
    Promise.all(advisories.map do |a|
      a.async_writable_by?(options[:current_user]).then do |writable_by|
        advisory_to_writable_by_hash[a] = writable_by
      end
    end).sync

    advisories.map do |advisory|
      writable = advisory_to_writable_by_hash[advisory]
      options[:repo_advisory_writable] = writable
      options[:removed_pvr_author] = !advisory.published? && !writable
      repository_advisory_hash(advisory, options)
    end
  end

  # The `options` hash param can be used to set additional options for the serializer. It is marked as "untyped" as
  # the way this method is called omits types and leads to false type failures. Example options:
  # - { repo_advisory_writable: true } # Return fields that require write_access to view, e.g. created_at, submission, author
  # - { removed_pvr_author: true } # The user is a removed pvr author and should see a simplified view of the draft advisory
  sig { params(advisory: T.nilable(RepositoryAdvisory), options: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def repository_advisory_hash(advisory, options = {})
    return nil unless advisory

    # Don't use .accepted here because it's a scope and takes us back to the db
    credits = options[:repo_advisory_writable] ? advisory.credits : advisory.credits.filter { |c| c.accepted? }

    GitHub::PrefillAssociations.prefill_associations(credits, :recipient)

    detailed_credits = advisory_credits_hash(credits, options)

    payload = T.let({
      ghsa_id: advisory.ghsa_id,
      cve_id: advisory.cve_id,
      url: advisory.api_url,
      html_url: advisory.html_url,
      summary: advisory.get_title(options[:current_user]),
      description: advisory.get_description(options[:current_user]),
      severity: advisory.severity == "moderate" ? "medium" : advisory.severity,
      author: options[:repo_advisory_writable] || options[:removed_pvr_author] ? simple_user_hash(advisory.author, options) : nil,
      publisher: simple_user_hash(advisory.publisher, options),
      identifiers: advisory.identifiers,
      state: advisory.api_state,
      created_at: options[:repo_advisory_writable] || options[:removed_pvr_author] ? time(advisory.created_at) : nil,
      updated_at: time(advisory.updated_at),
      published_at: time(advisory.published_at),
      closed_at: time(advisory.closed_at),
      withdrawn_at: time(advisory.withdrawn_at),
      submission: advisory.external && (options[:repo_advisory_writable] || options[:removed_pvr_author]) ? { accepted: advisory.accepted? } : nil,
      vulnerabilities: advisory.affected_products.map { |ap| repository_advisory_affected_product_hash(ap, options) },
      cvss_severities: {
        cvss_v3: {
          vector_string: advisory.cvss_v3,
          score: advisory.cvss_v3_score.zero? ? nil : advisory.cvss_v3_score },
        cvss_v4: {
          vector_string: advisory.cvss_v4,
          score: advisory.cvss_v4_score.zero? ? nil : advisory.cvss_v4_score }
      },
      cwes: advisory.cwes.map do |cwe|
        {
          cwe_id: cwe.cwe_id,
          name: cwe.name,
        }
      end,
      cwe_ids: advisory.cwes.map { |cwe| cwe.cwe_id },
      credits: detailed_credits.map do |credit|
        {
          login: credit.dig(:user, :login),
          type: credit[:type],
        }
      end,
      credits_detailed: detailed_credits,
      collaborating_users: options[:repo_advisory_writable] ? advisory.collaborating_users.map { |user| simple_user_hash(user, options) } : nil,
      collaborating_teams: if options[:repo_advisory_writable]
                             advisory.collaborating_teams_visible_to_user(options[:current_user]).map { |team| team_hash(team, options) }
                           else
                             nil
                           end,
      private_fork: options[:repo_advisory_writable] && advisory.workspace_repository ? simple_repository_hash(T.must(advisory.workspace_repository), options) : nil,
    }, T::Hash[Symbol, T.untyped])

    payload[:scope] = advisory.api_scope if FeatureFlag.vexi.enabled?(:innersource_advisories, options[:current_user], default: false) ||
      FeatureFlag.vexi.enabled?(:innersource_advisories, advisory.repository, default: false)

    # If the API changeset `deprecate_cvss` is active, don't add the `cvss` property to the payload.
    unless Api::SerializerOptions.from(options).changeset_active?(:deprecate_cvss)
      payload[:cvss] = {
        vector_string: advisory.cvss_v3,
        score: advisory.cvss_v3_score.zero? ? nil : advisory.cvss_v3_score,
      }
    end

    # Null out fields that a removed pvr author should not have access to.
    payload = ::RepositoryAdvisory.adjust_payload_fields_for_removed_pvr_author(payload) if options[:removed_pvr_author]

    # Remove fields that innersource advisories should not have.
    payload = ::RepositoryAdvisory.adjust_payload_for_innersource(payload) if advisory.innersource_advisories_enabled?

    payload
  end

  # With the deprecation of VEA, the API now returns empty values for vulnerable functions regardless of the data
  # in the database.  This is to avoid breaking the API contract before the official deprecation date has been reached.
  def repository_advisory_affected_product_hash(affected_product, options = {})
    return nil unless affected_product

    repository_advisory_affected_product_hash = {
      package: {
        ecosystem: affected_product.ecosystem&.downcase,
        name: affected_product.package,
      },
      vulnerable_version_range: affected_product.affected_versions,
      patched_versions: affected_product.patches,
    }

    if FeatureFlag.vexi.enabled?(:vea_api_populate_values_enabled, default: false)
      repository_advisory_affected_product_hash.merge!(vulnerable_functions: affected_product.affected_functions)
    else
      repository_advisory_affected_product_hash.merge!(vulnerable_functions: [])
    end

    repository_advisory_affected_product_hash
  end
end
