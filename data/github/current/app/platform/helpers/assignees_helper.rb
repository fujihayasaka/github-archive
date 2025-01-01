# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module AssigneesHelper
      include Kernel

      MAX_LOGIN_NAMES_LENGTH = 10
      COPILOT_SLUGS = [
        Apps::Privileged::CopilotSWEAgent::SLUG,
        Apps::Privileged::CopilotPullRequestReviewer::SLUG,
      ].freeze

      def extract_logins_from_string(logins)
        logins.split(/\s*,\s*/).take(MAX_LOGIN_NAMES_LENGTH)
      end

      def get_valid_assignees_from_logins(repository, logins)
        users = User.where(login: logins).to_a

        # Follows the logic inside `available_assignee_ids` except is performant as we only look at the users we care about
        valid_ids = repository.user_ids_with_privileged_access(actor_ids_filter: users.map(&:id))
        valid_users = users.select { |user| valid_ids.include?(user.id) }
        ArrayWrapper.new(valid_users)
      end

      sig do
        params(
          capabilities: T::Array[Enums::RepositorySuggestedActorFilter],
          viewer: T.nilable(User),
          repo: Repository,
          query: T.nilable(String),
          logins: T.nilable(T::Array[String])
        ).returns(Promise[T::Array[Bot]])
      end
      def async_bots(capabilities, viewer, repo, query: nil, logins: nil)
        is_assignable = capabilities.include?("can_be_assigned")
        is_authorable = capabilities.include?("can_be_author")

        if !is_assignable && !is_authorable
          return Promise.resolve(T.let([], T::Array[Bot]))
        end

        assignable_global_apps = ::Apps::Privileged.all_apps_with_capabilities([:installed_globally, :is_assignable], type: "Integration")

        # Exclude Copilot SWE agent if the repo does not have it enabled
        assignable_global_apps = assignable_global_apps.select do |app|
          app != Apps::Privileged.integration(:copilot_swe_agent) || repo.copilot_swe_agent_enabled?(viewer)
        end

        # If only authorable bots are requested, return only SWE Agent if no queries or logins are provided
        if is_authorable && !is_assignable && query.blank? && logins.blank?
          return Promise.all(assignable_global_apps.map(&:async_bot))
        end

        issues_authorable_integration_ids = is_authorable ? resource_authorable_integration_ids(repo, "issues") : []
        prs_authorable_integration_ids = is_authorable ? resource_authorable_integration_ids(repo, "pull_requests") : []

        Loaders::IntegrationInstallation::RepositoryForViewer.load(repo, viewer, is_assignable).then do |installations|
          Promise.all(installations.map(&:async_integration)).then do |integrations|
            # Need to include Global Apps, since they are installed everywhere.
            integrations += assignable_global_apps
            integrations.uniq!

            logins_contain_copilot_value = logins&.any? { |login| Search::Query::MACRO_COPILOT.casecmp?(login) || login.casecmp?("copilot") }

            filtered_integrations = integrations.select do |integration|
              if query.present?
                next false unless integration.name.downcase.include?(query.downcase) || integration.slug.downcase.include?(query.downcase)
              end

              if logins.present?
                next false unless logins.include?("app/#{integration.slug}") || (logins_contain_copilot_value && Apps::Privileged.capable?(:is_copilot, app: integration))
              end

              if is_authorable
                next false unless issues_authorable_integration_ids.include?(integration.id) ||
                  prs_authorable_integration_ids.include?(integration.id) ||
                  assignable_global_apps.include?(integration)
              end

              true
            end

            Promise.all(filtered_integrations.map(&:async_bot))
          end
        end
      end

      sig { params(repo: Repository, resource: String).returns(T::Array[Integer]) }
      def resource_authorable_integration_ids(repo, resource)
        IntegrationInstallation.with_resources_on(subject: repo, resources: resource, min_action: :write).pluck(:integration_id)
      end

      # This method sorts users and bots based on the following criteria:
      # 1. If the bot slug is either "copilot-swe-agent" or "copilot-pull-request-reviewer", it is placed at the top.
      # 2. Users are sorted by their login names.
      # 3. Other bots are sorted by their slugs.
      # 4. The final array contains unique elements based on their IDs.
      # 5. The order of elements is: Copilot bots (if present), users, and then other bots.
      sig { params(users: T.nilable(T::Array[User]), bots: T::Array[Bot]).returns(ArrayWrapper) }
      def sort_actors(users, bots)
        # There shouldn't be more than one Copilot bot suggested at the moment
        copilot_bots, other_bots = bots.partition { |bot| COPILOT_SLUGS.include?(bot.slug) }

        sorted_copilot_bots = copilot_bots.sort_by(&:slug)
        sorted_other_bots = other_bots.sort_by(&:slug)

        sorted_users = users&.sort_by(&:display_login) || []

        ArrayWrapper.new((sorted_copilot_bots + sorted_users + sorted_other_bots).compact.uniq(&:id))
      end

      def get_filtered_assignees_list(current_user, search_query, ids, typeahead_page_size, resolver_name)
        timer = Timer.start
        sanitized_query = ActiveRecord::Base.sanitize_sql_like(search_query)
        users = User.preload(:profile, :user_status)
          .left_joins(:profile)
          .where(id: ids)
          .where.not(type: "Bot")
          .merge(User.where("login LIKE ?", "%#{sanitized_query}%").or(Profile.where("name LIKE ?", "%#{sanitized_query}%")))
          .filter_spam_for(current_user)
          .references(:profile)

        # Sort by login & profile name, taking priority to those whom start with the search query.
        users = users.to_a.sort_by do |u|
          [
            u.display_login.start_with?(search_query) ? "0" : "1",
            u.safe_profile_name.start_with?(search_query) ? "0" : "1",
            u.display_login,
            u.safe_profile_name
          ]
        end

        timer.stop
        GitHub.dogstats.distribution("assignees.dist.fetch_filtered_users", timer.elapsed_ms,  tags: ["resolver:#{resolver_name}"])

        users.take(typeahead_page_size)
      end
    end
  end
end
