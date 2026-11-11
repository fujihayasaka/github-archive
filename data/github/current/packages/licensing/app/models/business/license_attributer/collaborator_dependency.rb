# typed: strict
# frozen_string_literal: true

module Business::LicenseAttributer::CollaboratorDependency
  extend T::Helpers

  extend ActiveSupport::Concern

  include GitHub::Memoizer

  requires_ancestor { Business::LicenseAttributer }

  # Outside collaborators on private repositories, excluding forks.
  # These users consume a license.
  sig { params(skip_cache: T.nilable(T::Boolean)).returns(T.nilable(T::Array[Integer])) }
  def private_outside_collaborator_ids(skip_cache: false)
    return @private_outside_collaborator_ids if defined?(@private_outside_collaborator_ids)

    @private_outside_collaborator_ids = T.let(
      business.license_attributer_cache.ids("private_outside_collaborator_ids", skip_cache: skip_cache) do
        business.outside_collaborator_ids(
          on_repositories_with_visibility: [:private],
          include_forks: false
        )
      end,
      T.nilable(T::Array[Integer])
    )
  end

  sig { returns(T.nilable(T::Hash[Integer, T::Array[String]])) }
  def private_outside_collaborator_org_repo_roles
    return @private_outside_collaborator_org_repo_roles if defined?(@private_outside_collaborator_org_repo_roles)

    outside_collaborator_user_id_to_repo_ids = if GitHub.single_business_environment?
      business.outside_collaborator_user_id_to_repo_ids
    else
      business_private_outside_repo_collaborators_hash
    end

    repo_ids = T.must(outside_collaborator_user_id_to_repo_ids).values.flatten.uniq
    repo_lookup = Repositories.domain.by_ids(repo_ids, batch_size: 1000).pluck(:id, :name, :organization_id).to_h do |id, name, org_id|
      [id, { org_id: org_id, name: name }]
    end

    org_ids = repo_lookup.values.map { |v| v[:org_id] }.compact.uniq
    org_id_to_display_login = Organization.where(id: org_ids).in_batches.each_with_object({}) do |batch, hash|
      hash.merge!(batch.pluck(:id, :display_login).to_h)
    end

    user_id_to_collabs = T.must(outside_collaborator_user_id_to_repo_ids).map do |user_id, repo_ids|
      collabs = repo_ids.map do |repo_id|
        org_id, repo_name = repo_lookup[repo_id]&.values_at(:org_id, :name)
        "#{org_id_to_display_login[org_id]}/#{repo_name}:Collaborator" if org_id && repo_name
      end
      [user_id, collabs.compact]
    end
    private_outside_collaborator_org_repo_roles = user_id_to_collabs.to_h

    @private_outside_collaborator_org_repo_roles = T.let(private_outside_collaborator_org_repo_roles, T.nilable(T::Hash[Integer, T::Array[String]]))
  end

  # Outside collaborators that do not consume a license.
  sig { params(skip_cache: T.nilable(T::Boolean)).returns(T.nilable(T::Array[Integer])) }
  def nonlicensed_outside_collaborator_ids(skip_cache: false)
    return @nonlicensed_outside_collaborator_ids if defined?(@nonlicensed_outside_collaborator_ids)

    @nonlicensed_outside_collaborator_ids = T.let(
      business.license_attributer_cache.ids("nonlicensed_outside_collaborator_ids", skip_cache: skip_cache) do
        business.outside_collaborator_ids(
          on_repositories_with_visibility: [:public],
          include_forks: true
        )
      end,
      T.nilable(T::Array[Integer])
    )
  end

  sig { returns(T::Array[Integer]) }
  memoize def business_guest_collaborator_ids
    business.guest_collaborator_ids
  end
end
