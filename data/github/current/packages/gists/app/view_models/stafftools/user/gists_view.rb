# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class GistsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

      attr_reader :user, :gists, :gist_type

      def page_title
        "#{user.display_login} - #{page_heading}"
      end

      def page_heading
        if gist_type
          "#{gist_type} gists".capitalize
        else
          "Public gists"
        end
      end

      def gists?
        gists.any?
      end

      def paginatable?
        gists.total_pages > 1
      end

      def visibility(gist)
        gist.visibility
      end

      def li_css(gist)
        css = []
        css << (gist.public? ? "public" : "private")
        css << "fork" if gist.fork?
        css.join(" ")
      end

      def span_symbol(gist)
        gist.public? ? "code-square" : "lock"
      end

      def route_classes(gist)
        if fs_offline? gist.route
          "route alert"
        else
          "route"
        end
      rescue GitHub::DGit::UnroutedError
        "route alert"
      end

      def route_display(gist)
        gist.route
      rescue GitHub::DGit::UnroutedError
        "unrouted"
      end

      private

      def fs_offline?(fs)
        return false if GitHub.enterprise?

        @offline_fileservers ||= GitHub::Stats::Site.dead_storage_servers
        @offline_fileservers.include? fs
      end
    end
  end
end
