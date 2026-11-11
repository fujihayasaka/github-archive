# typed: true
# frozen_string_literal: true

module Repository::ProgrammaticAccessDependency
  extend T::Helpers

  requires_ancestor { Repository }

  # Internal: Remove all leftover Permission records from various actors
  # including (Organization|User)ProgrammaticAccessGrants and
  # (Site)ScopedInstallations.
  #
  # Returns nil.
  def remove_programmatic_fine_grained_permissions(entry_point:)
    Permissions::Service.revoke_permissions_granted_on_subject(
      subject_id: self.id,
      subject_types: Repository::Resources.individual_type_prefixed_subject_types,
      entry_point: entry_point,
    )
  end
end
