# typed: strict
# frozen_string_literal: true

module Repositories
  module CustomProperties
    class UserEditPermissions < T::Struct
      # If true, a user has the org-level FGP and can edit properties for all repos in the org
      const :org, T::Boolean

      # If true, a user has the repo-level FGP and can edit properties for this repo
      const :repo, T::Boolean
    end
  end
end
