# typed: true
# frozen_string_literal: true

module Api::AuditLog::Helpers

  extend T::Helpers

  requires_ancestor { Api::App }
  requires_ancestor { Api::App::ErrorDependency }
  requires_ancestor { Api::App::DeliveryDependency }

  def build_and_execute_query
    deliver_error! 404 unless audit_api_enabled?

    query = ::Audit::Driftwood::Query.new_org_business_query(query_params)

    results = query.execute
    if GitHub.driftwood_enabled?
      setup_paging(results)
    else
      setup_legacy_paging(results)
    end

    deliver_query_results(results)
  end

  def build_and_execute_git_query
    deliver_error! 404 unless audit_rest_api_enabled?

    query = git_and_all_query

    results = query.execute
    if GitHub.driftwood_enabled?
      setup_paging(results)
    else
      setup_legacy_paging(results)
    end

    deliver_query_results(results)
  end

  def build_and_execute_all_query
    deliver_error! 404 unless audit_rest_api_enabled?

    query = git_and_all_query

    results = query.execute
    if GitHub.driftwood_enabled?
      setup_paging(results)
    else
      setup_legacy_paging(results)
    end

    deliver_query_results(results)
  end

  def git_and_all_query
    if GitHub.single_business_environment?
      ::Audit::Driftwood::Query.new_org_business_query(git_query_params)
    elsif events_type == :all
      ::Audit::Driftwood::Query.new_org_business_all_query(git_query_params)
    else # events_type == :git
      ::Audit::Driftwood::Query.new_org_business_git_query(git_query_params)
    end
  end

  private

  def deliver_query_results(results)
    options = { status:  200 }

    cost = results.try(:cost)
    if cost
      options[:audit_log_query_cost] = cost
    end

    deliver_raw(results.results, options)
  end

  def events_type
    if params[:include] == "all"
      :all
    elsif params[:include] == "git"
      :git
    else
      :web
    end
  end

  def query_params
    # We override the index_name in the test environment because audit
    # entries are logged to `audit_log-test` locally or
    # [`audit_log-test`..`audit_log-test-15`] in CI. They do not follow
    # the date slicing logic used in production.
    index_name = "audit_log#{Elastomer.env.postfix}" if Rails.env.test?

    query_args = {
      current_user: current_user,
      phrase: phrase,
      after: params[:after],
      before: params[:before],
      direction: direction,
      limit_history: !GitHub.single_business_environment?,
      per_page: per_page,
      public_platform: false,
      from_api: true,
      events_type: events_type,
    }.merge(identifier_params)

    unless GitHub.driftwood_enabled?
      query_args = query_args.merge(
        page: params[:page],
        index_name: index_name,
      )
    end

    query_args
  end

  def identifier_params
    {}
  end

  def git_query_params
    index_name = "audit_log#{Elastomer.env.postfix}" if Rails.env.test?

    query_args = {
      current_user: current_user,
      after: params[:after],
      before: params[:before],
      per_page: per_page,
      phrase: phrase,
      direction: direction,
      from_api: true,
      events_type: events_type,
    }.merge(identifier_params)

    unless GitHub.driftwood_enabled?
      query_args = query_args.merge(
        page: params[:page],
        index_name: index_name,
      )
    end

    query_args
  end

  def phrase
    if params[:phrase].present? && params[:phrase].include?("+") && GitHub.flipper[:audit_log_re_encode_phrase].enabled?(current_user)
      ERB::Util.url_encode(params[:phrase])
    else
      params[:phrase]
    end
  end

  def direction
    params[:order] || params[:sort] || params[:sort_dir] || "DESC"
  end

  def per_page
    pagination[:per_page] || 100
  end

  def setup_paging(results)
    if results.has_next_page?
      @links.add_current({ after: results.after_cursor, before: "" }, rel: "next")
    end

    if results.has_previous_page?
      @links.add_current({ before: "", after: "" }, rel: "first")
      @links.add_current({ after: "", before: results.before_cursor }, rel: "prev")
    end
  end

  def setup_legacy_paging(results)
    current_page = results.page || 1

    if results.results.size == per_page
      @links.add_current({ page: current_page + 1 }, rel: "next")
    end

    if current_page && current_page > 1
      @links.add_current({ page: 1 }, rel: "first")
      @links.add_current({ page: current_page - 1 }, rel: "prev")
    end
  end

  def audit_api_enabled?
    return true if GitHub.single_business_environment?

    audit_rest_api_enabled?
  end

  def audit_rest_api_enabled?
    return true if GitHub.single_business_environment? && AuditLogSettings.git_events_enabled?

    GitHub.driftwood_enabled?
  end
end
