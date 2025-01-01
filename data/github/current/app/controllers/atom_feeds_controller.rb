# typed: true
# frozen_string_literal: true

class AtomFeedsController < ApplicationController
  include GitHub::Authentication::Feed
  include OrganizationsHelper

  before_action :login_required
  before_action :org_members_only_org_feed, only: :org_show
  before_action :deny_saml_org_feeds, only: :org_show
  before_action :ensure_timeline_available

  layout false

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    only: [:org_show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:actor_show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    only: [:user_show]

  def org_show # rubocop:todo GitHub/UseRestfulActions
    @feed_title = "Private Feed for the #{current_organization} Organization"
    respond_to do |format|
      format.atom do
        set_header_for_no_index_and_no_follow
        render "events/index"
      end
    end
  end

  def actor_show # rubocop:todo GitHub/UseRestfulActions
    @feed_title = "Private Activity Feed for #{current_user}"
    respond_to do |format|
      format.atom do
        set_header_for_no_index_and_no_follow
        render "events/index"
      end
    end
  end

  def user_show # rubocop:todo GitHub/UseRestfulActions
    @feed_title = "Private Feed for #{current_user}"

    respond_to do |format|
      format.atom do
        set_header_for_no_index_and_no_follow
        render "events/index"
      end

      format.json do
        docs_url = "#{GitHub.developer_help_url}/v3/activity/events/#list-events-that-a-user-has-received"
        render json: gone_payload(docs_url), status: 410
      end
    end
  end

  private

  # Private: Actions that can respond to atom requests.
  #
  # Returns an Array or Strings.
  def feed_actions
    %w( org_show user_show actor_show )
  end

  def ensure_timeline_available
    render status: 503, plain: unavailable_message if events_timeline.unavailable?
  end

  def unavailable_message
    message = "The events timeline is currently unavailable."
    message += " Please check https://githubstatus.com for more information." unless GitHub.enterprise?
    message
  end

  def org_members_only_org_feed
    render_404 unless current_organization
  end

  def deny_saml_org_feeds
    if current_organization.saml_sso_enabled? || current_organization.enterprise_managed_user_enabled?
      render_404
    end
  end

  def events_timeline_key
    case params[:action]
    when "actor_show"
      "actor:#{current_user.id}"
    when "org_show"
      "org:#{current_organization.id}"
    else
      "user:#{current_user.id}"
    end
  end
end
