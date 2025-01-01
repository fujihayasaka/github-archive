# typed: strict
# frozen_string_literal: true

# This class handles Repository and Gist access disabling and enabling.
#
# See GitRepositoryAccess for requirements
class RepositoryGitRepositoryAccess < GitRepositoryAccess
  extend T::Sig

  sig { params(git_repository: Repository).void }
  def initialize(git_repository)
    @type = T.let("repository", String)

    super
  end
end
