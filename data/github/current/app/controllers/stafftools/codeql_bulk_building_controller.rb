# typed: true
# frozen_string_literal: true

module Stafftools
  class CodeqlBulkBuildingController < StafftoolsController
    before_action :dotcom_required

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Billing,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index], optional: true

    def index
      # Note that because there is one record per repo/language pair there could be more
      # than one record per repository. Therefore we paginate over the distinct
      # repository ids, and fetch the associated languages for each repo later.

      repo_ids_query = all_onboarded_repo_ids
      total_repos_count = repo_ids_query.count

      if params[:query].present?
        repo_ids_query = search_onboarded_repo_ids(params[:query])
        filtered_repos_count = repo_ids_query.count
      else
        filtered_repos_count = nil
      end

      onboarded_repos_page = repo_ids_query.paginate(page: current_page, per_page: 500)
      onboarded_repo_languages_page = onboarded_repo_languages(onboarded_repos_page.map(&:repository_id))

      render "stafftools/codeql_bulk_building/index", locals: {
        total_count: total_repos_count,
        filtered_count: filtered_repos_count,
        onboarded_repos: onboarded_repos_page,
        onboarded_repo_languages: onboarded_repo_languages_page,
      }
    end

    def onboard # rubocop:todo GitHub/UseRestfulActions
      render "stafftools/codeql_bulk_building/onboard"
    end

    def onboard_submit # rubocop:todo GitHub/UseRestfulActions
      unless params[:repositories].present? && params[:language].present?
        flash[:error] = "Missing required parameters"
        redirect_to :back
        return
      end

      repo_ids = input_to_repository_ids(params[:repositories])
      repo_ids.each_slice(500).each do |ids|
        CodeqlBulkBuilderOnboardJob.perform_later(repos_and_languages: ids.map { |id| [id, params[:language]] })
      end

      flash[:notice] = "Background job triggered to onboard #{repo_ids.length} repositories."
      redirect_to :back
    end

    def offboard # rubocop:todo GitHub/UseRestfulActions
      render "stafftools/codeql_bulk_building/offboard"
    end

    def offboard_submit # rubocop:todo GitHub/UseRestfulActions
      unless params[:repositories].present? && params[:language].present?
        flash[:error] = "Missing required parameters"
        redirect_to :back
        return
      end

      repo_ids = input_to_repository_ids(params[:repositories])
      repo_ids.each_slice(500).each do |ids|
        CodeqlBulkBuilderOffboardJob.perform_later(repos_and_languages: ids.map { |id| [id, params[:language]] })
      end

      flash[:notice] = "Background job triggered to offboard #{repo_ids.length} repositories."
      redirect_to :back
    end

    private

    # Converts a whitespace/newline separated list of NWOs and org names into repository IDs.
    def input_to_repository_ids(query)
      repo_names, user_names = query.split.partition { |s| s.include?("/") }.map(&:to_set)

      repo_ids = Set.new
      repo_names.each_slice(500).each do |names|
        repo_ids += ::Repository.with_names_with_owners(names).pluck(:id)
      end
      repo_ids += ::Repository.where(owner_login: user_names).pluck(:id)

      repo_ids
    end

    # Construct a query for repo ids limited to a certain search.
    # The query is expected to either be whitespace-separated list of
    # repo NWOs or user/org names.
    def search_onboarded_repo_ids(query)
      repo_ids = input_to_repository_ids(query)
      CodeqlBulkBuilderConfig
        .select(:repository_id)
        .where(repository_id: repo_ids)
        .order(repository_id: :asc)
        .distinct
    end

    # Construct a query for all onboarded repo ids, assuming no search terms.
    def all_onboarded_repo_ids
      CodeqlBulkBuilderConfig
        .select(:repository_id)
        .order(repository_id: :asc)
        .distinct
    end

    # For a given set of repo ids, fetch the onboarded languages for each repo.
    # Returns type: [Repository, language[]][]
    def onboarded_repo_languages(repo_ids)
      repos_by_id = ::Repository.where(id: repo_ids).index_by(&:id)
      CodeqlBulkBuilderConfig
        .where(repository_id: repo_ids)
        .order(repository_id: :asc)
        .pluck(:repository_id, :language)
        .group_by(&:first)
        .map { |k, v| [repos_by_id[k], v.map(&:second).sort] }
    end
  end
end
