# typed: true
# frozen_string_literal: true

class EventsController < ApplicationController
  # 404s in Proxima
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesPushes,
    only: [:index]

  def index
    respond_to do |format|
      format.html do
        render "events/index", layout: false, formats: [:atom], content_type: :atom
      end
      format.atom { render "events/index", layout: false }
      format.json do
        docs_url = "#{GitHub.developer_help_url}/v3/activity/events/#list-public-events"
        render json: gone_payload(docs_url), status: 410
      end
    end
  end

  private

  # Handle auth specifics for feed requests.
  include GitHub::Authentication::Feed

  # Private: Actions that can response to atom requests.
  #
  # Returns an Array of Strings.
  def feed_actions
    %w(index)
  end

  def events_timeline_key
    "public"
  end
end
