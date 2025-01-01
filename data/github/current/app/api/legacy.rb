# typed: true
# frozen_string_literal: true

class Api::Legacy < Api::App
  PER_PAGE = 100

  # DEPRECATED: Will be removed in API v4.
  get "/legacy/issues/search/:owner/:repo/:state/:q", operation_id: :deprecated do
    @route_owner = Platform::NoOwnerBecause::DEPRECATED
    control_access :search_issues,
      repo: repo = this_repo,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    query = ::Search::Queries::IssueQuery.new \
      phrase:        params[:q],
      current_user:  current_user,
      remote_ip:     remote_ip,
      repo_id:       repo.id,
      source_fields: false,
      context:       "legacy-api-issues-search"

    state = params[:state]
    if state.present?
      query.qualifiers[:state].clear
      query.qualifiers[:state].must @state
    end

    results = results_for(query)

    prefill_for_issues_search(results)
    issues = results.map { |h| issue_for_api(h["_model"]) }

    deliver_raw issues: issues
  end

  # DEPRECATED: Will be removed in API v4.
  get "/legacy/repos/search/:q", operation_id: :deprecated do
    @route_owner = Platform::NoOwnerBecause::DEPRECATED
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: false,
      allow_user_via_granular_actor: false

    if params[:q].present?
      page = params[:start_page].to_i
      page = 1 if page < 1

      query = ::Search::Queries::RepoQuery.new(
                phrase: params[:q],
                language: params[:language],
                current_user: current_user,
                remote_ip: remote_ip,
                cap_filter: cap_filter,
                sort: sort_expression,
                page: page,
                per_page: PER_PAGE,
              )
      results = results_for(query)

      repos = results.results.map do |h|
        Api::Serializer.serialize(:legacy_repository_search_result_hash, h["_model"],
          search_hit: h["_source"], score: h["_score"].to_f)
      end

      deliver_raw repositories: repos
    else
      deliver_raw repositories: []
    end
  end

  # DEPRECATED: Will be removed in API v4.
  get "/legacy/user/search/:q", operation_id: :deprecated do
    @route_owner = Platform::NoOwnerBecause::DEPRECATED
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: false,
      allow_user_via_granular_actor: false

    if params[:q].present?
      page = params[:start_page].to_i
      page = 1 if page < 1

      query = ::Search::Queries::UserQuery.new(
                phrase: params[:q],
                current_user: current_user,
                remote_ip: remote_ip,
                sort: sort_expression,
                page: page,
                per_page: PER_PAGE,
              )
      results = results_for(query)

      users = results.results.map do |h|
        Api::Serializer.serialize(:legacy_user_search_result_hash, h["_model"],
          search_hit: h["_source"], score: h["_score"].to_f)
      end

      deliver_raw users: users
    else
      deliver_raw users: []
    end
  end

  # DEPRECATED: Will be removed in API v4.
  get "/legacy/user/email/:email", operation_id: :deprecated do
    @route_owner = Platform::NoOwnerBecause::DEPRECATED

    e = params[:email]
    user = User.with_profile_email(e) if e

    control_access :public_site_information,
      resource: Platform::PublicResource.new(resource: user),
      allow_integrations: false,
      allow_user_via_granular_actor: false

    if user
      hash = Api::Serializer.serialize(:legacy_user_email_result_hash, user)
      deliver_raw user: hash
    else
      deliver_error 404
    end
  end

  private

  def results_for(query)
    begin
      query.execute
    rescue Search::Query::MaxOffsetError => boom
      deliver_error! 422, message: boom.message
    rescue StandardError => boom # rubocop:todo Lint/RescueException
      failbot(env, exception: boom, fatal: "NO")
      Search::Results.empty
    end
  end

  def prefill_for_issues_search(results)
    issues = results.results.map { |result| result["_model"] }
    GitHub::PrefillAssociations.prefill_associations(issues, :labels)
  end

  def issue_for_api(issue)
    Api::Serializer.serialize(:legacy_issue_search_result_hash, issue)
  end

  def sort_expression
    sort = params[:sort] || params[:s]
    return nil if sort.blank?

    if AcceptedSortOrderings.include?(params[:order])
      direction = params[:order]
    elsif AcceptedSortOrderings.include?(params[:o])
      direction = params[:o]
    else
      direction = "desc"
    end

    [sort, direction]
  end

end
