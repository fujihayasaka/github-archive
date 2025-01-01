# typed: true
# frozen_string_literal: true

require "tilt"
require "erb"
require "generated_pages/page"

module GitHub
  module Pages
    class Creator
      class Context
        # Internal: Generate a GitHub URL with the specified path.
        #
        # paths - Array of strings representing the GitHub path.
        #
        # Returns a GitHub URL string.
        def github_url_for(*paths)
          url = GitHub.ssl? ? "https" : "http"
          url << "://" << GitHub.host_name
          url << "/"   << paths.join("/")
          url
        end
      end

      def initialize(repo, user, params)
        @repo   = repo
        @user   = user
        @params = params
      end

      # Internal: Creates the gh-pages branch in the current repo and adds all
      # the files (markup and assets) for the generated page to it.
      #
      # Returns nothing.
      def run
        files = {}
        ref = @repo.heads.read(@repo.pages_branch)

        if ref.exist?
          # Try to grab the existing CNAME file
          if cname_blob = @repo.blob(ref.commit.oid, "CNAME")
            # If there's an existing CNAME file, add it to the new index
            files["CNAME"] = cname_blob.data
          end
        end

        if @repo.is_user_pages_repo?
          message = "Replace #{@repo.pages_branch} branch with page content via GitHub"
        else
          message = "Create #{@repo.pages_branch} branch via GitHub"
        end

        # Record field values so they can be brought back later
        params_to_serialize = @params.slice(:name, :tagline, :body, :google)
        params_to_serialize[:note] = "Don't delete this file! It's used internally to help with page regeneration."

        # Generate the commit and bump the pages branch
        ref.append_commit(
          { message: message, author: @user },
          @user,
          sign: true
        ) do |files|
          files.add("params.json", GitHub::JSON.yajl_encode(params_to_serialize, pretty: true))
        end
      end
    end
  end
end
