# typed: true
# frozen_string_literal: true

module Repository::Prefillable
  extend ActiveSupport::Concern

  class_methods do
    # Public: Preloads Repository#owner, Repository#open_issues_count,
    #         Repository#all_forks_count
    #
    # repos    - An Array of Repositories.
    # mirror   - Boolean whether to prefill Repository#mirror (default: true)
    # owner    - Boolean whether to prefill Repository#owner and
    #            Repository#organization (default: true)
    # internal - Boolean whether to prefill Repository#internal_repository (default: false)
    #
    # Returns nothing.
    def prefill_associations(repos, mirror: true, owner: true, internal: false)
      associations_to_prefill = [:network, :page, :parent, :repository_license, :repository_licenses, :template_repository_clone, :group_map]
      associations_to_prefill << :owner << :organization if owner
      associations_to_prefill << :mirror if mirror
      associations_to_prefill << :internal_repository if internal

      GitHub::PrefillAssociations.prefill_associations(repos, associations_to_prefill)

      GitHub::PrefillAssociations.prefill_batch_method(repos, :open_issues_count)
      GitHub::PrefillAssociations.prefill_batch_method(repos.select(&:private?), :all_forks_count)
      GitHub::PrefillAssociations.prefill_batch_method(repos, :topic_names)
    end
  end
end
