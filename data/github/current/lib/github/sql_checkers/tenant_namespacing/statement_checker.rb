# typed: true
# frozen_string_literal: true

class GitHub::SQLCheckers::TenantNamespacing::StatementChecker < GitHub::SQLCheckers::StatementChecker
  USERS_DISP_LOGIN_REGEX = /(?!.+business_id)select.+users.+WHERE.+display_login.+/i.freeze

  # find queries that query the users table with display_login as a condition
  # that do NOT include a business_id (tenant context) as well
  # this is a violation because display_login is only unique per-tenant
  #
  # log or raise so we can remediate any offensive queries
  def check(queries:, connection_class: nil)
    # Bypass check if we're in a stafftools tenant
    # v1 of stafftools tenant support will be unscoped to avoid breaking changes to stafftools
    # See ADR discussion in https://github.com/github/proxima/pull/2288
    # This may be removed in the future once we have a tenant aware stafftools functionality
    return if GitHub::CurrentTenant.stafftools_tenant?

    # Return if we're not testing in multitenant mode as this can catch queries which are deliberately different in
    # multitenant vs single tenant mode.
    return unless GitHub.multi_tenant_enterprise?

    all_queries = queries.join("\n")
    query_found = check_for_unsafe_display_login(all_queries)
    # We do a second pass for now because query comments that include the
    # currently running test name can include "display_name", causing a false
    # positive
    query_found = query_found && queries.any? do |q|
      scrubbed = scrub_values_from_query(q)
      # Ignore queries that only reference display_login in the ORDER BY clause
      ignoring_order_by = scrubbed.split(/ORDER\s+BY/i, 2).first
      ignoring_order_by.match?(USERS_DISP_LOGIN_REGEX)
    end

    return unless query_found

    # production, log to splunk
    if report_errors? && frame_info = GitHub::SQLCheckers::StacktraceParser.first_relevant_frame_info(caller)
      scrubbed_query = scrub_values_from_query(queries[0])
      log_query_info(frame_info, scrubbed_query)
    end

    # test and dev, raise
    if raise_errors?
      raise_and_report_error("github-tenant-namespacing", queries, queries[0], caller)
    end

    query_found
  end

  private

  def log_query_info(frame_info, query)
    file = frame_info[:path]
    method = frame_info[:method]
    query = scrub_values_from_query(query)

    # log to splunk in production
    GitHub::Logger.log({
      request_id: GitHub.context[:request_id],
      msg: "Unsafe display_login query without tenant context",
      file: file,
      method: method,
      query: query
    })
  end

  # returns true or false
  def check_for_unsafe_display_login(queries)
    queries.match?(USERS_DISP_LOGIN_REGEX)
  end

  def error_for(message)
    GitHub::SQLCheckers::TenantNamespacing::UnsafeDisplayLoginQueryError.new(message)
  end

  def error_message(queries, query, frame, **context)
    String.new("\n\n") << <<~MSG
      Unsafe query executed without tenant context provided:
      #{queries.join("\n")}

      Query with a condition for users.display_login must also include users.business_id
      since display_login is only unique per-tenant.

      Please reach out to #proxima with any questions.
    MSG
  end
end
