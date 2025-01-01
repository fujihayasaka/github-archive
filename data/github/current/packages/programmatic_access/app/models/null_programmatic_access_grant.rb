# typed: true
# frozen_string_literal: true

class NullProgrammaticAccessGrant < UserProgrammaticAccessGrant
  include GitHub::Memoizer

  # Overridden method from ProgrammaticActorPermissionGrantable
  memoize def can_have_granular_user_permissions?
    return false unless target.instance_of?(User)
    target == user_programmatic_access&.owner
  end

  def repository_selection
    "none"
  end

  def permission_results
    {}
  end
end
