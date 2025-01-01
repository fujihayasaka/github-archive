# typed: true
# frozen_string_literal: true

class SecurityAdvisoriesController < ApplicationController
  include GitHub::Authentication::Feed

  # Security advisories are public

  # CAP bypass is fine here as advisories are public.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    only: [:index]

  def index
    increment_request_count

    respond_to do |format|
      format.html do
        render "security_advisories/index", layout: false, formats: [:atom], content_type: :atom
      end
      format.atom { render "security_advisories/index", layout: false }
    end
  end

  private

  def increment_request_count
    GitHub.dogstats.increment("security_advisories.request", tags: ["decrease_days:#{decrease_days?}", "decrease_queries: #{decrease_queries?}"])
  end

  def decrease_days?
    feature_enabled_globally_or_for_current_user?(:advisories_atom_decrease_days)
  end

  def decrease_queries?
    feature_enabled_globally_or_for_current_user?(:advisories_atom_decrease_queries)
  end

  def feed_actions
    %w(index)
  end
end
