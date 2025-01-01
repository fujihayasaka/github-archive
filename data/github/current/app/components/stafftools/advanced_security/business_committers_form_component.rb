# typed: true
# frozen_string_literal: true

class Stafftools::AdvancedSecurity::BusinessCommittersFormComponent < ApplicationComponent
  BATCH_SIZE = 1000

  attr_reader :additional_committers, :additional_committers_csv, :error, :maximum_committers, :active_committers, :this_business

  def initialize(this_business:, entities: nil, sku: GitHub::Turboghas::SKU::Bundled)
    ActiveRecord::Base.connected_to(role: :reading) do
      @this_business = this_business
      @additional_committers = nil
      @additional_committers_csv = nil
      @error = nil
      summary = @this_business.advanced_security_license_for_sku(sku:).entity_summary
      @maximum_committers = summary.maximum_committers
      @active_committers = summary.active_committers
      @sku = sku

      # GET - entities are nil
      unless entities.nil?
        entities = entities.each_line.map(&:strip).reject(&:blank?).uniq

        if entities.blank?
          # POST - empty form
          @error = "Please provide a list of Organizations and Repositories"
        else
          # POST - values
          repos, missing = resolve_entities_to_repos(entities)

          @additional_committers = this_business.advanced_security_license_for_sku(sku:).seat_usage_increase_if_enabled_for_repos(repos.to_a)
          @additional_committers_csv = Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: this_business, committer_type: :ADDITIONAL_COMMITTERS, repository_ids: repos.to_a, sku:)

          if missing.present?
            @error = "Not Found: #{ missing.to_a.sort.join(", ") }"
          end
        end
      end
    end
  end

  private

  # Takes a combined list of org names and repo NWOs and resolves them to the
  # set of all repository objects indentified by the NWOs or contained in the orgs.
  # Returns the set of repository objects, and any missing NWOs or orgs.
  def resolve_entities_to_repos(entities)
    repos = Set.new
    missing = Set.new

    nwos, orgs = entities.partition { |line| line.include?("/") }.map(&:to_set)

    resolve_orgs_to_repos(orgs, repos, missing)
    resolve_nwos_to_repos(nwos, repos, missing)

    [repos, missing]
  end

  # Takes a list of org names and resolves them to the set of all repository objects contained in the orgs.
  # The set of repository objects is added to the repos set, and any missing orgs are added to the missing set.
  def resolve_orgs_to_repos(orgs, repos, missing)
    orgs.each_slice(BATCH_SIZE) do |orgs|
      orgs_scope = organizations.where(login: orgs)

      # if we found less organizations than expected, work out which ones were missing
      if orgs_scope.count != orgs.size
        found = orgs_scope.pluck(:login).map(&:downcase).to_set
        not_found = orgs.reject { |org| found.include?(org.downcase) }
        missing.merge(not_found)
      end

      org_ids = orgs_scope.pluck(:id).to_set

      Repository.can_enable_advanced_security.where(owner: org_ids).in_batches(of: BATCH_SIZE) do |batch|
        repos.merge batch.pluck(:id)
      end
    end
  end

  # Takes a list of repo NWOs and resolves them to the repository objects.
  # The set of repository objects is added to the repos set, and any missing repos are added to the missing set.
  def resolve_nwos_to_repos(nwos, repos, missing)
    nwos.each_slice(BATCH_SIZE) do |nwos|
      nwos_scope = Repository.with_names_with_owners(nwos.map(&:downcase)).where(Repository::arel_table[:owner_id].in(organizations))

      # if we found less repositories than expected, work out which ones were missing
      # we use the full scope for verifying repositories exist and filter out any repositories that cannot have advanced security later
      if nwos_scope.count != nwos.size
        found = nwos_scope.map { |repo| repo.nwo.downcase }.to_set
        not_found = nwos.reject { |nwo| found.include?(nwo.downcase) }
        missing.merge(not_found)
      end

      # do not include any repos that cannot have advanced security in the results
      repos.merge nwos_scope.can_enable_advanced_security.pluck(:id)
    end
  end

  # returns a scope that contains all the organizations belonging to this business
  def organizations
    if GitHub.single_business_environment?
      Organization.all
    else
      @this_business.organizations
    end
  end
end
