# typed: true
# frozen_string_literal: true

class Stafftools::AdvancedSecurity::OrganizationCommittersFormComponent < ApplicationComponent
  BATCH_SIZE = 1000

  attr_reader :additional_committers, :additional_committers_csv, :error, :maximum_committers, :active_committers, :this_user

  def initialize(this_user:, entities: nil, sku: GitHub::Turboghas::SKU::Bundled)
    ActiveRecord::Base.connected_to(role: :reading) do
      @this_user = this_user
      @additional_committers = nil
      @additional_committers_csv = nil
      @error = nil
      summary = @this_user.advanced_security_license_for_sku(sku:).entity_summary
      @maximum_committers = summary.maximum_committers
      @active_committers = summary.active_committers

      # GET - entities are nil
      unless entities.nil?
        entities = entities.each_line.map(&:strip).reject(&:blank?).uniq

        if entities.blank?
          # POST - empty form
          @error = "Please provide a list of Repositories"
        else
          # POST - values
          repos, missing = find_repos(entities)

          @additional_committers = this_user.advanced_security_license.seat_usage_increase_if_advanced_security_enabled_for_repos(repos.to_a)
          @additional_committers_csv = Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: this_user, committer_type: :ADDITIONAL_COMMITTERS, repository_ids: repos.to_a, sku:)

          if missing.present?
            @error = "Not Found: #{ missing.to_a.sort.join(", ") }"
          end
        end
      end
    end
  end

  private

  def find_repos(names)
    missing = Set.new
    repos = Set.new

    repos_scope = @this_user.repositories.where(name: names.map { |name| name.downcase.delete_prefix("#{@this_user.login.downcase}/") })

    # if we found fewer repositories than expected, work out which ones were missing
    # we use the full scope for verifying repositories exist and filter out any repositories that cannot have advanced security later
    if repos_scope.count != names.size
      found = Set.new
      repos_scope.in_batches(of: BATCH_SIZE) do |batch|
        found.merge batch.map { |repo| repo.name.downcase }
      end
      not_found = names.reject { |name| found.include?(name.downcase) }
      missing.merge(not_found)
    end

    # do not include any repos that cannot have advanced security in the results
    repos_scope.can_enable_advanced_security.in_batches(of: BATCH_SIZE) do |batch|
      repos.merge batch.pluck(:id)
    end

    [repos, missing]
  end
end
