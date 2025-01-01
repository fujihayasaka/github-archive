# typed: true
# frozen_string_literal: true

module Gist::StaffTools
  extend T::Helpers

  requires_ancestor { Gist }

  def disable_access(reason, disabling_user, **opts)
    DisableGistAccessJob.perform_later(self, reason, disabling_user, **opts)
  end

end
