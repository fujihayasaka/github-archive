# typed: true

module Stafftools
  class LargeFilesView
    module PreviewTogglerHelper

      abstract!

      sig { abstract.returns(::Repository) }
      def git_lfs_configurable; end
    end
  end
end

module Configurable
  module GitLfs

    abstract!

    sig { abstract.returns(Configuration) }
    def config; end
  end
end
