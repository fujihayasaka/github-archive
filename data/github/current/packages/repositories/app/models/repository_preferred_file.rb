# typed: true
# frozen_string_literal: true

class RepositoryPreferredFile < ApplicationRecord::Domain::Repositories
  self.table_name = "preferred_files"

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain return_type: T.nilable(Repositories::IRepository)

  enum :filetype, {
    code_of_conduct: 0,
    codeowners: 1,
    contributing: 2,
    funding: 3,
    readme: 4,
    support: 5,
    license: 6,
    security: 7,
    no_preferred_files_found_in_repo: 8,
  }

  NO_PREFERRED_FILES_TYPE = "no_preferred_files_found_in_repo"
  ALL_TYPES = filetypes.keys
  VALID_TYPES = filetypes.keys - [NO_PREFERRED_FILES_TYPE]
end
