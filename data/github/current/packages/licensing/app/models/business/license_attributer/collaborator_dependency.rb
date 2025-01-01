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
