# typed: true
# frozen_string_literal: true

class BoomtownController < ApplicationController
  extend T::Sig

  # CAP not required, this is an employee-only controller for testing exceptions
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:index]

  layout "site"

  # for failbot testing
  def index
    # Enterprise CI currently relies on accessing boomtown to ensure Failbot
    # is setup correctly.
    return render_404 unless employee? || site_admin?
    if params[:job] == "true"
      BoomtownJob.perform_later(magic_number: 42, cause: params[:cause])
      render plain: "Job submitted"
    elsif params[:cause] == "true"
      # allows testing of exceptions with cause
      begin
        fail "the underlying cause"
      rescue # rubocop:todo Lint/GenericRescue
        fail "the outer wrapper (#{GitHub.host_name})"
      end
    elsif params[:redaction_test]
      Failbot.push(implicit_sensitive: "Data not marked as sensitive that should be filtered")
      Failbot.push_sensitive(explicit_sensitive: "Data marked as sensitive")
      # simulate an exception that needs redaction
      begin
        fail Zlib::Error, "failed to zip private private private"
      rescue # rubocop:todo Lint/GenericRescue
        raise "outer exception, no PII here! (#{GitHub.host_name})"
      end
    elsif params[:redaction_key_test]
      Failbot.report!(RuntimeError.new("Error to be redacted"), {
        catalog_service: "github/boomtown", # This should go through to Sentry unredacted
        "gh.tenant.slug": "foo", # this is not allowed to go to Sentry
        unknown_key: true, # since it is an unknown key, this should be scrubbed
        "http.route": "fake email: example@example.com" # http.route is allowed to go to Failbot, but email address in its string value should get regexed out
      })
      fail "Failed"
    elsif params[:ruby_upgrade]
      call_kwargs_method({ say: "This method will throw a warning for kwargs. Find the logged exception in the github-ruby-warnings project in Sentry." })
    elsif params[:db_reconnect]
      begin
        adapter = ApplicationRecord::Domain::Internal.connection
        adapter.exec_query("SELECT 1;")
        adapter.instance_variable_get(:@raw_connection).close
        adapter.exec_query("SELECT 1;")
        render plain: "Auto reconnected"
      rescue => exception
        Failbot.report!(exception)
        render plain: "Failed to reconnect"
      ensure
        adapter.reconnect!
      end
    else
      fail "BOOM (#{GitHub.host_name})"
    end
  end

  private

  def call_kwargs_method(say:)
    render plain: "#{say}"
  end
end
