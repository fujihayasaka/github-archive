# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :filter
      attr_reader :page

      def repo_li_css(repo)
        css = []
        css << (repo.public? ? "public" : "private")
        css << "fork" if repo.fork?
        css << "mirror" if repo.mirror?
        css.join(" ")
      end

      def repo_span_symbol(repo)
        repo.public? ? "repo" : "lock"
      end

      def repositories_query
        return @query if defined?(@query)
        scope = ::Repository.active.preload(:mirror, :owner, { parent: :owner })
        @query = case selected_filter
        when "private"
          scope.private_not_internal_scope
        when "internal"
          scope.internal_scope
        when "public"
          scope.public_scope
        when "anonymous_git_access"
          scope.with_anonymous_git_access
        else
          scope
        end
        @query = @query.order("created_at DESC")
        @query = @query.paginate(page: @page) unless @page.nil?
        @query
      end

      def anonymous_git_access_repo_ids
        return @anon_access_repo_ids if defined?(@anon_access_repo_ids)
        @anon_access_repo_ids = if selected_filter == "anonymous_git_access"
          repositories_query.map(&:id)
        else
          ::Repository.where(id: repositories_query.map(&:id)).
            with_anonymous_git_access.
            pluck(:id)
        end
      end

      def anonymous_git_access_enabled_for_repo?(repo)
        return false unless repo.anonymous_git_access_available?

        anonymous_git_access_repo_ids.include?(repo.id)
      end

      def selected_filter
        @selected_filter ||= if filter_labels.keys.include?(@filter)
          @filter
        else
          filter_labels.keys.first
        end
      end

      def selected_filter_label
        filter_labels[selected_filter]
      end

      def filter_labels
        labels =
            {
              "all" => "All repositories",
              "private" => "Private repositories",
              "internal" => "Internal repositories",
              "public" => "Public repositories",
            }.tap { |l| l.delete("public") unless GitHub.public_repositories_available? }
        labels["anonymous_git_access"] = "Public repositories with anonymous Git access enabled" if GitHub.anonymous_git_access_enabled?
        labels
      end
    end
  end
end
