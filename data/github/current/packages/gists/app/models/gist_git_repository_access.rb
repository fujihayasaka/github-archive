# typed: strict
# frozen_string_literal: true

# This class handles Gist access disabling and enabling.
#
# See GitRepositoryAccess for requirements
class GistGitRepositoryAccess < GitRepositoryAccess
  sig { params(git_repository: Gist).void }
  def initialize(git_repository)
    @type = T.let("gist", String)

    super
  end
end
