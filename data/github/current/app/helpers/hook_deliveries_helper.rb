# typed: true
# frozen_string_literal: true

module HookDeliveriesHelper
  include Kernel
  HOOKSHOT_MAX_DELIVERIES = 50

  def current_hook
    @current_hook ||= (
      Hook.find_by(id: T.unsafe(self).params[:hook_id]) ||
      Hook.find_by(id: T.unsafe(self).params[:webhook_id]) ||
      raise(ApplicationController::ErrorHandlingDependency::NotFound)
    )
  end

  def parse_search_query(query)
    allowed_delivery_api_queries = [:since, :until, :status, :status_code, :events, :redelivery, :guid, :repo_id, :installation_id]
    parsed_query = Search::ParsedQuery.parse(query, terms: allowed_delivery_api_queries)
    parsed_query.select! { |query_item| query_item.is_a?(Array) } # ignore any parts of the query not in our list of terms
    # TODO: should do some kind of validation/error handling if one item
    # term is provided multiple times, because right now we'll only take the
    # last one
    Hash[parsed_query]
  end

  def hookshot
    @hookshot ||= Hookshot::Client.ui_client_for_parent current_hook.hookshot_parent_id
  end

  # check whether a redelivery for the given guid after the provided time is
  # included in the /deliveries output
  def deliveries_updated?(guid, updated_after)
    params = { since: updated_after,
               guid: guid,
               limit: 1 } # we don't actually care about the data returned, just that there is data
    status, data = hookshot.deliveries_for_hook(current_hook.id, params)
    status == 200 && !data["deliveries"].empty? # TODO should we do something else if there's not a 200?
  end

  def fetch_deliveries
    @query = T.unsafe(self).params[:deliveries_q]
    params_for_search = parse_search_query(@query)
    params_for_search[:limit] = HOOKSHOT_MAX_DELIVERIES
    if T.unsafe(self).params[:next_cursor]
      params_for_search[:cursor] = T.unsafe(self).params[:next_cursor]
    end

    status, data = hookshot.deliveries_for_hook(current_hook.id, params_for_search)
    next_cursor = data.dig("page_info", "next_cursor")
    deliveries = data["deliveries"].present? ? Hookshot::Delivery.load(data["deliveries"]) : []
    outages = data["outages"]
    error = data&.fetch("message", nil)

    Hooks::DeliveriesView.new(
      current_hook: current_hook,
      current_user: T.unsafe(self).current_user,
      deliveries: deliveries,
      outages: outages,
      next_cursor: next_cursor,
      error: error,
      status: status)
  end

  def paginated_deliveries?
    T.unsafe(self).params[:next_cursor].present?
  end

  def paginate_deliveries(hook, next_cursor, query)
    return unless next_cursor # if `next_cursor` is nil there's no more pages
    T.unsafe(self).render partial: "hook_deliveries/paginate_delivery_logs",
      locals: { hook: hook, last_delivery_guid: nil, next_cursor: next_cursor, hook_deliveries_query: query }
  end

  def pre_ignoring_indentation(&block)
    content = T.unsafe(self).capture(&block)
    lines = content.gsub(/\A\n/, "").split("\n")
    indentation = /\A(\s*)/.match(lines.first) && $1.length
    unindented = lines.join("\n").gsub(/^\s{#{indentation}}/, "")

    T.unsafe(self).content_tag(:pre, unindented.html_safe) # rubocop:disable Rails/OutputSafety
  end
end
