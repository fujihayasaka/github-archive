# typed: true
# frozen_string_literal: true

class ReposPicker::RepositoriesController < ApplicationController
  include ReposPicker::CurrentOwnerDependency
  include ReposPicker::RepositoriesPayloadDependency

  depends_on_clusters \
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories

  layout false

  before_action :login_required
  before_action :ensure_correct_owner_scope

  MAX_ITEMS = 100
  MAX_BIZ_ORGS = 500
  INJECTED_TERMS = "in:name sort:name-asc"

  sig { void }
  def index
    results = repo_query.execute

    render json: {
      items: repositories_payload(results.results.map { |r| r["_model"] }),
      totalCount: results.total,
    }
  end

  sig { void }
  def count # rubocop:disable GitHub/UseRestfulActions
    return head :not_found if params[:q].blank?

    results = repo_query.count_with_timeout
    render json: {
      totalCount: results.total,
    }
  end

  private

  sig { returns(Search::Queries::RepoQuery) }
  def repo_query
    query = Search::Queries::RepoQuery.new(
      current_user: current_user,
      cap_filter: cap_filter,
      user_session: user_session,
      remote_ip: remote_ip,
      phrase: phrase,
      include_forks: true,
      binary_fork_filter: true,
      visibility_and_execution: true,
      per_page: MAX_ITEMS,
      page: 1,
    )

    org_logins = if current_owner
      [T.must(current_owner).display_login]
    elsif current_enterprise
      T.must(current_enterprise).organizations.limit(MAX_BIZ_ORGS).pluck(:display_login)
    end
    query.qualifiers[:org].clear.must org_logins

    query
  end

  sig { returns(String) }
  def phrase
    result = "#{params[:q].to_s.strip} #{INJECTED_TERMS}"
    result = "visibility:#{params[:visibility]} #{result}" if params[:visibility].present?

    result
  end

  def ensure_correct_owner_scope
    return head :not_found unless current_owner || current_enterprise
    head :not_found if current_owner && current_enterprise
  end
end
