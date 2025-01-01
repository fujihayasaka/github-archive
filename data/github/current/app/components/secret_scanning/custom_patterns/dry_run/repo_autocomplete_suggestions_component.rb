# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    module DryRun
      class RepoAutocompleteSuggestionsComponent < ApplicationComponent
        include SecretScanningCustomPatternsHelper

        attr_reader :owner, :query

        BATCH_SIZE = 1000

        def initialize(
          owner:,
          query:,
          user:,
          limit: DRY_RUN_REPO_SELECTOR_DEFAULT_SUGGESTIONS,
          authorized_orgs: [])
          @owner = owner
          @query = query
          @user = user
          @limit = limit
          @authorized_orgs = authorized_orgs
        end

        memoize def matching_repositories
          if @query.blank?
            return []
          end

          ActiveRecord::Base.connected_to(role: :reading) do
            suggestions = like_query
            if suggestions.empty?
              return []
            end

            suggestions = secret_scanning_enabled(suggestions)

            exact_match = look_for_exact_match(suggestions)

            suggestions = sort_and_limit(suggestions)
            suggestions = suggestions.prepend(exact_match) if exact_match

            @matching_repositories = suggestions.uniq.compact
          end

          @matching_repositories
        end

        def like_query
          repos_in_scope = []

          owner, repo = @query.split("/")
          # load org owned repositories
          base_rel = Repository.active.where(owner_id: @authorized_orgs.map(&:id))

          suggestable_org_ids = @authorized_orgs.select { |o| o.display_login.include?(owner) }
          suggestable_repo_ids = repo.nil? ? base_rel.with_substring(:name, owner) : base_rel.with_substring(:name, repo)

          suggestions = base_rel
            .where(owner_id: suggestable_org_ids)
            .then { |rel| repo.nil? ? rel.or(suggestable_repo_ids) : rel.and(suggestable_repo_ids) }
            .order("id asc")
            .to_a

          if @owner.is_a?(Business) && ::AdvancedSecurity::Features::Business::AdvancedSecurity.new(@owner).feature_available_for_user_repositories?
            suggestions += user_suggestions
          end

          suggestions
        end

        def user_suggestions
          if GitHub.enterprise?
            query = ActiveRecord::Base.sanitize_sql_like(@query.to_s.strip.downcase)
            Repository
              .active
              .user_owned
              .where(["repositories.name LIKE :query OR repositories.owner_login LIKE :query", { query: "%#{query}%" }])
          else
            @owner.user_namespace_repositories(query: @query)
          end
        end

        def secret_scanning_enabled(suggestions)
          repo_ids = suggestions.map(&:id)
          # TODO move this out of component?
          secret_scanning_repo_ids = SecretScanning::Services::CustomPatternsService.new(@user).validate_secret_scanning_repositories(repo_ids)
          return [] if secret_scanning_repo_ids.nil?
          suggestions.select { |repo| secret_scanning_repo_ids.include?(repo.id) }
        end

        def sort_and_limit(suggestions)
          suggestions.sort_by(&:name).take(@limit)
        end

        def look_for_exact_match(suggestions)
          suggestions.find { |repo| repo.name == @query }
        end
      end
    end
  end
end
