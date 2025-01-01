# typed: strict
# frozen_string_literal: true

module Copilot
  module ContentExclusion
    extend T::Sig

    ConfigAndRules = T.type_alias { T::Hash[Copilot::ContentExclusionConfiguration, T::Array[Copilot::ContentExclusion::Rule]] }

    GITHUB_OWNER_AND_OR_REPO_NAME_VALID_REGEX = /\A[a-zA-Z0-9\-_.\/]+\z/

    # This method determines if the Copilot Content Exclsuions is available for a specific object.
    # Unlike #has_any_active_rules?, this method will not check if the feature is being used by the object, only that it may be.
    #
    # How we determine this:
    #   1. If the object is a repository, we check if the owner is an organization. If so, we check if the organization has copilot enabled.
    #   2. If the object is an organization, we check if it has copilot enabled.
    #   3. If the object is a business, we check if content exclusion is available..
    #
    # @param object [Repository, Organization] The object to check if the Copilot Content Exclusion feature is available for.
    # @return [Boolean] Whether or not the Copilot Content Exclusion feature is available for the given object.
    sig { params(object: T.any(::Repository, ::Organization, ::Business)).returns(T::Boolean) }
    def self.is_available?(object)
      GitHub.tracer.in_span("Copilot::ContentExclusion.is_available?") do |_span|
        if object.is_a?(::Repository)
          return false unless object.owner&.organization?
          org = T.cast(object.owner, ::Organization)
        elsif object.is_a?(::Organization)
          org = object
        elsif object.is_a?(::Business)
          return Copilot::Business.new(object).content_exclusion_available?
        else
          return false
        end

        Copilot::Organization.new(org).copilot_enabled?
      end
    end

    # This method returns the content exclusion rules for a given repository.
    # Repositories can only have content exclusion rules if they are owned by an organization.
    #
    # The rules will be pulled from the organization's enterprise if it exists, the
    # organization that owns the repository, as well as any neighboring organizations
    # under the same enterprise.
    sig { params(repo: ::Repositories::IRepository).returns(ConfigAndRules) }
    def self.rules_for_repo(repo)
      GitHub.tracer.in_span("copilot_organization.rules_for_repo") do |_span|
        return {} unless repo.owner.is_a?(::Organization)

        org = T.cast(repo.owner, ::Organization)

        organization_ids = [T.must(org.id)]
        business_ids = org.business? ? org.business_ids : []

        all_relevant_configs = all_relevant_configurations(business_ids:, organization_ids:)
        return {} if all_relevant_configs.empty?

        all_relevant_configs.map do |config|
          rules = config.resolve_rules_for_repo_url(repo.ssh_url_for_api)
          next if rules.empty?
          [config, rules]
        end.compact.to_h
      end
    end


    # Returns an array of content exclusion rules for a given set of repository URLs.
    # Each set of rules will contain the rules that apply to the given repository URL specifically, and
    # any wildcard rules
    sig do
      params(
        url_strings: T::Array[String],
        business_ids: T::Array[Integer],
        organization_ids: T::Array[Integer],
        neighbour_influence: T::Boolean
      ).returns(T::Array[ConfigAndRules])
    end
    def self.rules_for_repo_urls(url_strings, business_ids: [], organization_ids: [], neighbour_influence: false)
      return [] if url_strings.empty?
      return [] if organization_ids.empty? && business_ids.empty?

      GitHub.tracer.in_span("Copilot::ContentExclusion.rules_for_repo_urls") do |span|
        span.set_attribute("gh.copilot.content_exclusion.url.count", url_strings.count)
        GitHub.dogstats.histogram("copilot.content_exclusion.request_url_count", url_strings.count)

        all_relevant_configs = all_relevant_configurations(business_ids: business_ids, organization_ids: organization_ids)

        # are we including configs from multiple enterprises
        shares_enterprise = T.let(false, T::Boolean)
        if neighbour_influence
          first_business_id = get_config_parent_business(all_relevant_configs.first)&.id

          if first_business_id.present?
            # assume they share an enterprise
            shares_enterprise = true
            all_relevant_configs.each do |config|
              seen_before = get_config_parent_business(config)&.id.equal?(first_business_id)
              # as soon as we see its different, break
              unless seen_before
                shares_enterprise = false
                break
              end
            end
          end
        end

        url_strings.map do |url_string|
          all_relevant_configs.map do |config|
            rules = config.resolve_rules_for_repo_url(url_string)
            next if rules.empty?

            # For an GA theory, we want to know when this `config` influenced the rules returned but belonging to a neighbouring organization
            if neighbour_influence
              # this is asking, does the user have a copilot seat assigment where this config is resolved from
              is_neighbour = organization_ids.exclude?(config.organization_id)

              # there are rules which is a wildcard (`*`), thus included
              has_wildcard = rules.find { |r| r.is_all_scoped? }.present?

              GitHub.dogstats.increment("copilot.content_exclusion.returned_rules", tags: [
                "is_neighbour:#{is_neighbour}",
                "has_wildcard:#{has_wildcard}",
                "shares_enterprise:#{shares_enterprise}"
              ])

              GitHub.logger.info("Content exclusions returned rules for a neighbouring organization",
                "gh.org.id" => config.organization_id,
                "has_wildcard" => has_wildcard,
                "shares_enterprise" => shares_enterprise,
              ) if is_neighbour
            end

            [config, rules]
          end.compact.to_h
        end
      end
    end

    # Returns a set of rules that contain only the wildcard scope to apply to all files in the filesystem.
    sig { params(business_ids: T::Array[Integer], organization_ids: T::Array[Integer]).returns(ConfigAndRules) }
    def self.rules_for_all_files_scope(business_ids: [], organization_ids: [])
      return {} if organization_ids.empty? && business_ids.empty?
      GitHub.tracer.in_span("copilot_user.rules_for_all_files_scope") do
        GitHub.dogstats.increment("copilot.content_exclusion.request_all_files_scope")

        all_relevant_configurations(business_ids:, organization_ids:).map do |config|
          rules = config.resolve_rules_for_all_files_scope
          next if rules.empty?

          [config, rules]
        end.compact.to_h
      end
    end

    sig { params(config: T.nilable(ContentExclusionConfiguration)).returns(T.nilable(::Business)) }
    def self.get_config_parent_business(config)
      config&.business || config&.organization&.business
    end

    sig { params(business_ids: T::Array[Integer], organization_ids: T::Array[Integer]).returns(T::Array[Copilot::ContentExclusionConfiguration]) }
    def self.all_relevant_configurations(business_ids: [], organization_ids: [])
      GitHub.tracer.in_span("Copilot::ContentExclusion.all_relevant_configurations") do |span|
        return [] if organization_ids.empty? && business_ids.empty?

        neighbor_org_ids = only_neighboring_org_ids(organization_ids)
        all_org_ids = organization_ids + neighbor_org_ids

        result = Copilot::ContentExclusionConfiguration
          .with_business_or_organization_ids(business_ids, all_org_ids)
          .with_document
          .by_resource
          .includes(:organization, resource: [:owner])
          .select { |config| copilot_enabled?(config.organization || config.resource) }
          .to_a

        span.set_attribute("gh.copilot.ignore.neighboring_org.count", all_org_ids.count)
        span.set_attribute("gh.copilot.ignore.config.count", result.count)

        result
      end
    end

    sig { params(entity: T.any(::Organization, ::Business)).returns(T::Boolean) }
    def self.copilot_enabled?(entity)
      return Copilot::Organization.new(entity).copilot_enabled? if entity.is_a?(::Organization)

      copilot_business = Copilot::Business.new(entity)
      copilot_business.copilot_enabled? && copilot_business.content_exclusion_available?
    end

    # Returns an array of organization IDs that belong to the same businesses as the org_ids.
    #
    # @param org_ids [Array<Integer>] An array of organization IDs.
    # @param business_ids [Array<Integer>] An array of business IDs.
    # @return [Array<Integer>] An array of relevant organization IDs.
    sig { params(org_ids: T::Array[Integer]).returns(T::Array[Integer]) }
    def self.only_neighboring_org_ids(org_ids)
      GitHub.tracer.in_span("Copilot::ContentExclusion.neighboring_organization_ids") do |_span|
        business_ids = ::Business::OrganizationMembership.where(organization_id: org_ids).pluck(:business_id)

        ::Business::OrganizationMembership.where(business_id: business_ids).where.not(organization_id: org_ids).pluck(:organization_id).uniq
      end
    end
  end
end
