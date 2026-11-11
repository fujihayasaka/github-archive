# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class BillingDataIntegrityChecker
    BATCH_SIZE = 1_000

    BUSINESS_ADVANCED_SECURITY_KEY = "advanced_security"
    BUSINESS_ADVANCED_SECURITY_LICENSE_COUNT_KEY = "advanced_security.seats"
    BUSINESS_SECRET_PROTECTION_LICENSE_COUNT_KEY = "secret_scanning.license_count"
    BUSINESS_CODE_SECURITY_LICENSE_COUNT_KEY = "code_security.license_count"
    REPOSITORY_ADVANCED_SECURITY_KEY = "advanced_security.user_enabled"
    REPOSITORY_CODE_SECURITY_KEY = "code_security.user_enabled"
    REPOSITORY_SECRET_PROTECTION_KEY = "token_scanning.user_enabled"

    VOLUME_BUNDLED_VALUE = "true"
    METERED_BUNDLED_VALUE = "enabled_with_metered_billing"
    VOLUME_UNBUNDLED_VALUE = "split_volume_all"
    METERED_UNBUNDLED_VALUE = "split_metered"
    VOLUME_CODE_SECURITY_VALUE = "split_code_security_only"
    VOLUME_SECRET_PROTECTION_VALUE = "split_secret_scanning_only"

    DISABLED_VALUES = T.let([nil, false, "false", "off"], T::Array[T.any(NilClass, T::Boolean, String)])
    BUNDLED_VALUES = T.let([VOLUME_BUNDLED_VALUE, METERED_BUNDLED_VALUE], T::Array[String])
    UNBUNDLED_VALUES = T.let([VOLUME_UNBUNDLED_VALUE, METERED_UNBUNDLED_VALUE, VOLUME_CODE_SECURITY_VALUE, VOLUME_SECRET_PROTECTION_VALUE], T::Array[String])

    SUSPENSION_GRACE_PERIOD = T.let(90.days, ActiveSupport::Duration)
    DOWNGRADE_GRACE_PERIOD = T.let(90.days, ActiveSupport::Duration)

    class Problem < T::Enum
      enums do
        AdvancedSecurity = new("stale_advanced_security_configuration_entries")
        CodeSecurity = new("stale_code_security_configuration_entries")
        SecretProtection = new("stale_secret_protection_configuration_entries")
      end
    end

    class RepositoryData < T::Struct
      const :id, Integer
      const :organization_id, Integer
      const :business_id, Integer
      const :is_archived, T::Boolean
    end

    include GitHub::Memoizer

    sig { params(business_ids: T::Array[Integer], repository_ids: T.nilable(T::Array[Integer]), block: T.nilable(T.proc.params(problem: Problem, repositories: T::Array[RepositoryData]).void)).void }
    def self.check(business_ids:, repository_ids: nil, &block)
      new(business_ids:, repository_ids:).check(&block)
    end

    sig { params(business_ids: T::Array[Integer], repository_ids: T.nilable(T::Array[Integer])).void }
    def self.clean(business_ids:, repository_ids: nil)
      new(business_ids:, repository_ids:, clean: true).check
    end

    sig { returns(T::Array[Integer]) }
    attr_reader :business_ids

    sig { returns(T.nilable(T::Set[Integer])) }
    attr_reader :repository_ids

    sig { params(business_ids: T::Array[Integer], repository_ids: T.nilable(T::Array[Integer]), clean: T::Boolean).void }
    def initialize(business_ids:, repository_ids: nil, clean: false)
      @business_ids = T.let(business_ids.uniq, T::Array[Integer])
      @repository_ids = T.let(repository_ids&.to_set, T.nilable(T::Set[Integer]))
      @clean = clean
    end

    sig { returns(T::Boolean) }
    def clean?
      !!@clean
    end

    sig { params(block: T.nilable(T.proc.params(problem: Problem, repositories: T::Array[RepositoryData]).void)).void }
    def check(&block)
      # Default to reporting stale data to Datadog and Splunk via #report.
      block ||= proc { |problem, repositories| report(problem:, repositories:) }

      businesses_by_id.each_value do |business|
        if business.suspended? && business.suspended_at > SUSPENSION_GRACE_PERIOD.ago
          GitHub.logger.warn("skip.within_suspension_grace_period", {
            "code.namespace": self.class.name,
            "gh.business.id": business.id,
            "gh.business.slug": business.slug,
          })

          next
        end

        if business.downgraded_to_free_plan? && business.downgraded_at > DOWNGRADE_GRACE_PERIOD.ago
          GitHub.logger.warn("skip.within_downgrade_grace_period", {
            "code.namespace": self.class.name,
            "gh.business.id": business.id,
            "gh.business.slug": business.slug,
          })

          next
        end

        if business.advanced_security_sku_trial_enabled_for_entity?
          GitHub.logger.warn("skip.advanced_security_sku_trial_enabled", {
            "code.namespace": self.class.name,
            "gh.business.id": business.id,
            "gh.business.slug": business.slug,
          })

          next
        end

        check_for_stale_advanced_security_configuration_entries(business, &block)
        check_for_stale_code_security_configuration_entries(business, &block)
        check_for_stale_secret_protection_configuration_entries(business, &block)
        check_for_stale_license_count_configuration_entries(business)
      end
    end

    private

    sig { returns(T::Hash[Integer, ::Business]) }
    memoize def businesses_by_id
      businesses = ::Business.where(id: business_ids).find_each(batch_size: BATCH_SIZE).to_a
      Configurable.preload_configuration(businesses)
      businesses.index_by(&:id)
    end

    # Returns a minimal T::Struct to represent the repository data we need,
    # indexed by business ID.
    sig { returns(T::Hash[Integer, T::Array[RepositoryData]]) }
    memoize def repositories_by_business_id
      business_ids_by_organization_id = {}

      business_ids
        .each_slice(BATCH_SIZE) do |batch_of_business_ids|
          ::Business::OrganizationMembership
            .where(business_id: batch_of_business_ids)
            .in_batches(of: BATCH_SIZE) do |batch_of_memberships|
              batch_of_memberships
                .pluck(:business_id, :organization_id)
                .each do |business_id, organization_id|
                  business_ids_by_organization_id[organization_id] = business_id
                end
            end
        end

      result = {}

      business_ids_by_organization_id
        .each_key
        .each_slice(BATCH_SIZE) do |batch_of_organization_ids|
          repositories_for_organizations =
            ::Repository # ::Repository is important to differentiate from SecurityProductsEnablement::Repository
              .from("`repositories` USE INDEX (index_repos_on_owner_id_public_active_primary_lang_name_id)")
              .active
              .private_scope
              .where(owner_id: batch_of_organization_ids)

          # If no repository IDs were given during instantiation, all
          # repository IDs are permitted. Otherwise, the repository ID
          # found must be in the list of allowed IDs given.
          if repository_ids
            repositories_for_organizations = repositories_for_organizations
              .where(id: repository_ids)
          end

          repositories_for_organizations
            .in_batches(of: BATCH_SIZE) do |batch_of_repositories|
              batch_of_repositories
                .pluck(:owner_id, :id, :maintained)
                .each do |organization_id, repository_id, maintained|
                  business_id = business_ids_by_organization_id.fetch(organization_id)

                  result[business_id] ||= []
                  result[business_id] << RepositoryData.new(
                    id: repository_id,
                    organization_id: organization_id,
                    business_id: business_id,
                    is_archived: !maintained,
                  )
                end
            end
        end

      result
    end

    sig { params(business: ::Business, block: T.proc.params(problem: Problem, repositories: T::Array[RepositoryData]).void).void }
    def check_for_stale_advanced_security_configuration_entries(business, &block)
      repositories =
        if !business.advanced_security_purchased_for_entity? || !business.advanced_security_products_bundled?
          find_repositories_with_configuration_entry(named: REPOSITORY_ADVANCED_SECURITY_KEY, business:)
        else
          []
        end

      return if repositories.empty?

      yield Problem::AdvancedSecurity, repositories
    end

    sig { params(business: ::Business, block: T.proc.params(problem: Problem, repositories: T::Array[RepositoryData]).void).void }
    def check_for_stale_code_security_configuration_entries(business, &block)
      repositories =
        if !business.advanced_security_purchased_for_entity? || business.advanced_security_products_bundled? || business.secret_protection_volume_purchased_for_entity?
          find_repositories_with_configuration_entry(named: REPOSITORY_CODE_SECURITY_KEY, business:)
        else
          []
        end

      return if repositories.empty?

      yield Problem::CodeSecurity, repositories
    end

    sig { params(business: ::Business, block: T.proc.params(problem: Problem, repositories: T::Array[RepositoryData]).void).void }
    def check_for_stale_secret_protection_configuration_entries(business, &block)
      repositories =
        if !business.advanced_security_purchased_for_entity? || business.code_security_volume_purchased_for_entity?
          find_repositories_with_configuration_entry(named: REPOSITORY_SECRET_PROTECTION_KEY, business:)
        elsif business.advanced_security_products_bundled?
          secret_protection_enabled_repositories =
            find_repositories_with_configuration_entry(named: REPOSITORY_SECRET_PROTECTION_KEY, business:)
          secret_protection_enabled_repositories.reject!(&:is_archived)
          advanced_security_enabled_repositories =
            find_repositories_with_configuration_entry(named: REPOSITORY_ADVANCED_SECURITY_KEY, business:)

          # For bundled businesses, having Secret Protection enabled is only
          # allowed if Advanced Security is also enabled. Here, we find
          # repositories with Secret Protection enabled and then remove
          # those that have Advanced Security enabled so we're left with only
          # the forbidden combination of having SP enabled and GHAS disabled.
          # Note that this combination *is* allowed if the private repository
          # is archived.
          secret_protection_enabled_repositories - advanced_security_enabled_repositories
        else
          []
        end

      return if repositories.empty?

      yield Problem::SecretProtection, repositories
    end

    sig { params(named: String, business: ::Business).returns(T::Array[RepositoryData]) }
    def find_repositories_with_configuration_entry(named:, business:)
      repositories_by_id_for_business =
        repositories_by_business_id.fetch(business.id, []).index_by(&:id)
      matching_repository_ids = []

      repositories_by_id_for_business
        .each_key
        .each_slice(BATCH_SIZE) do |batch_of_repository_ids_for_business|
          batch_of_matching_repository_ids =
            Configuration::Entry
              .named(named)
              .targeting_repository_ids(batch_of_repository_ids_for_business)
              .pluck(:target_id)
          matching_repository_ids.concat(batch_of_matching_repository_ids)
        end

      repositories_by_id_for_business.values_at(*matching_repository_ids)
    end

    sig { params(problem: Problem, repositories: T::Array[RepositoryData]).void }
    def report(problem:, repositories:)
      problem_string = problem.serialize
      business_ids = repositories.map(&:business_id).uniq
      repository_ids = repositories.map(&:id).uniq

      GitHub.dogstats.increment(
        "security_products_enablement.security_billing_data_integrity_checker.businesses",
        tags: ["problem:#{problem_string}", "clean:#{clean?}"],
        by: business_ids.count,
      )

      GitHub.dogstats.increment(
        "security_products_enablement.security_billing_data_integrity_checker.repositories",
        tags: ["problem:#{problem_string}", "clean:#{clean?}"],
        by: repository_ids.count,
      )

      repositories.each do |repository|
        business = businesses_by_id.fetch(repository.business_id)

        GitHub.logger.warn(problem_string, {
          "code.namespace": self.class.name,
          "gh.business.id": business.id,
          "gh.business.slug": business.slug,
          "gh.org.id": repository.organization_id,
          "gh.repo.id": repository.id,
          "gh.repo.archived": repository.is_archived,
        })
      end

      return unless clean?

      case problem
      when Problem::AdvancedSecurity
        destroy_configuration_entries_for_repositories(named: REPOSITORY_ADVANCED_SECURITY_KEY, repository_ids:)
      when Problem::CodeSecurity
        destroy_configuration_entries_for_repositories(named: REPOSITORY_CODE_SECURITY_KEY, repository_ids:)
      when Problem::SecretProtection
        destroy_configuration_entries_for_repositories(named: REPOSITORY_SECRET_PROTECTION_KEY, repository_ids:)
      else
        T.absurd(problem)
      end

      GitHub.logger.warn("#{problem_string}.clean", {
        "code.namespace": self.class.name,
        "gh.business.count": business_ids.count,
        "gh.repo.count": repository_ids.count,
      })
    end

    sig { params(named: String, repository_ids: T::Array[Integer]).void }
    def destroy_configuration_entries_for_repositories(named:, repository_ids:)
      repository_ids
        .each_slice(BATCH_SIZE) do |batch_of_repository_ids|
          entries =
            Configuration::Entry
              .named(named)
              .targeting_repository_ids(batch_of_repository_ids)
              .to_a

          ActiveRecord::Base.connected_to(role: :writing) do
            entries.each(&:destroy!)
          end
        end
    end

    sig { params(business: ::Business).void }
    def check_for_stale_license_count_configuration_entries(business)
      case business.config.get(BUSINESS_ADVANCED_SECURITY_KEY)
      when VOLUME_BUNDLED_VALUE
        # GHAS is volume, bundled. Only the Advanced Security SKU license count is preserved.
        report_stale_license_count_configuration_entry(business:, named: BUSINESS_SECRET_PROTECTION_LICENSE_COUNT_KEY)
        report_stale_license_count_configuration_entry(business:, named: BUSINESS_CODE_SECURITY_LICENSE_COUNT_KEY)
      when VOLUME_UNBUNDLED_VALUE
        # GHAS is volume, unbundled. Only Secret Protection and Code Security SKU license counts are preserved.
        report_stale_license_count_configuration_entry(business:, named: BUSINESS_ADVANCED_SECURITY_LICENSE_COUNT_KEY)
      when VOLUME_SECRET_PROTECTION_VALUE
        # GHAS is volume, unbundled, Secret Protection only. Only the Secret Protection SKU license count is preserved.
        report_stale_license_count_configuration_entry(business:, named: BUSINESS_ADVANCED_SECURITY_LICENSE_COUNT_KEY)
        report_stale_license_count_configuration_entry(business:, named: BUSINESS_CODE_SECURITY_LICENSE_COUNT_KEY)
      when VOLUME_CODE_SECURITY_VALUE
        # GHAS is volume, unbundled, Code Security only. Only the Code Security SKU license count is preserved.
        report_stale_license_count_configuration_entry(business:, named: BUSINESS_ADVANCED_SECURITY_LICENSE_COUNT_KEY)
        report_stale_license_count_configuration_entry(business:, named: BUSINESS_SECRET_PROTECTION_LICENSE_COUNT_KEY)
      else
        # GHAS is disabled or metered. No license counts are applicable or preserved.
        report_stale_license_count_configuration_entry(business:, named: BUSINESS_ADVANCED_SECURITY_LICENSE_COUNT_KEY)
        report_stale_license_count_configuration_entry(business:, named: BUSINESS_SECRET_PROTECTION_LICENSE_COUNT_KEY)
        report_stale_license_count_configuration_entry(business:, named: BUSINESS_CODE_SECURITY_LICENSE_COUNT_KEY)
      end
    end

    sig { params(business: ::Business, named: String).void }
    def report_stale_license_count_configuration_entry(business:, named:)
      value = business.config.raw(named)
      return unless value

      GitHub.logger.warn("stale_license_count_configuration_entry", {
        "code.namespace": self.class.name,
        "gh.business.id": business.id,
        "gh.business.slug": business.slug,
        "configuration_entry.name": named,
        "configuration_entry.value": value,
      })

      GitHub.dogstats.increment(
        "security_products_enablement.security_billing_data_integrity_checker.stale_license_count_configuration_entries",
        tags: ["configuration_entry_name:#{named}", "clean:#{clean?}"],
      )

      return unless clean?

      ActiveRecord::Base.connected_to(role: :writing) do
        business.config.delete(named)
      end

      GitHub.logger.warn("stale_license_count_configuration_entry.clean", {
        "code.namespace": self.class.name,
        "gh.business.id": business.id,
        "gh.business.slug": business.slug,
        "configuration_entry.name": named,
      })
    end
  end
end
