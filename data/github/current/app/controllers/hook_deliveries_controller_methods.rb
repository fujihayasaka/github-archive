# typed: true
# frozen_string_literal: true

module HookDeliveriesControllerMethods
  extend ActiveSupport::Concern
  include HookDeliveriesHelper
  extend T::Helpers

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))

    before_action :authorization_required
    before_action :sudo_filter
    before_action :find_delivery, only: [:show, :payload]
    before_action :return_early_if_polling, only: [:index, :redeliveries]

    helper_method :delivery_guid, :current_hook, :current_context, :render_deliveries_page?

    rate_limit_requests \
      max: 30,
      ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL,
      key: :hook_delivery_rate_limit_key,
      at_limit: :hook_delivery_rate_limit_record
  end

  include Hookshot::DeliverJobLogger

  def index
    @deliveries_view = fetch_deliveries
    if @deliveries_view.error
      raise Hookshot::BadResponseError.new(@deliveries_view.status, @deliveries_view.error)
    else
      respond_to do |format|
        format.html { render "hook_deliveries/index" }
      end
    end
  end

  def show
    if @delivery.present?
      gauge_payload_and_response_size
      delivery_view = Hooks::DeliveryView.new hook: current_hook, delivery: @delivery, current_user: current_user
    end

    respond_to do |format|
      format.html { render "hook_deliveries/show", layout: false, locals: { delivery_view: delivery_view } }
    end
  end

  def payload
    if @delivery.present?
      render json: @delivery.payload
    else
      render json: ""
    end
  end

  def redeliver
    begin
      Hook::DeliverySystem.redeliver(delivery_guid, current_hook)
      GitHub.dogstats.increment("webhooks_redelivery_attempted", tags: ["method: ui"])
    rescue Hookshot::PayloadTooLarge => e
      log_params = {
        error: e,
        target: current_hook.installation_target,
        parent: current_hook.hookshot_parent_id,
        guid: delivery_guid,
        hook_ids: current_hook.id,
      }

      log_payload_too_large_error(log_params)
      report_error(e)
    end

    respond_to do |format|
      format.html { render "hook_deliveries/redeliver", layout: false }
    end
  end

  def redeliveries
    @deliveries_view = fetch_deliveries
    if @deliveries_view.error
      raise Hookshot::BadResponseError.new(@deliveries_view.status, @deliveries_view.error)
    else
      respond_to do |format|
        format.html { render "hook_deliveries/index", layout: false }
      end
    end
  end

  private

  # This is here specifically for redeliveries. When someone triggers a redlivery, it takes time
  # for the delivery to be reach the end user. However, we want to asynchronously update the hook
  # deliveries UI once  redelivery is successful. As a result the HTML in the hook_deliveries/redelivery
  # file polls the index endpoint for latest deliveries. This `before_action` is meant to return early
  # to that caller with every poll request until `deliveries_updated?` eventually returns true.
  # When this happens we proceed to fetch deliveries from hookshot-go that happend after params[:updated_after]
  def return_early_if_polling
    if params[:updated_after].present? && !deliveries_updated?(delivery_guid, params[:updated_after])
      head :accepted
    end
  end

  def target_for_conditional_access
    target = current_hook.installation_target

    # Allow Proxima Stafftools to fetch webhook deliveries from non-staffship tenants
    if GitHub.multi_tenant_enterprise? && user_feature_enabled?(:proxima_webhooks_access)
      # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      return :no_target_for_conditional_access if GitHub::CurrentTenant.stafftools_tenant?
      # rubocop:enable GitHub/SpecifyTargetForConditionalAccess
    end

    # If no target is found, we'd result in a 404
    return :no_target_for_conditional_access unless target # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    return target.owner if target.respond_to?(:owner)
    target
  end

  def delivery_guid
    params[:guid]
  end

  def delivery_id
    params[:id]
  end

  def find_delivery
    status, resp = hookshot.delivery_for_hook(delivery_id, current_hook.id, { "include_payload" => true })
    if status == 200
      @delivery = Hookshot::Delivery.load resp
    elsif status == 404
      # Sometimes because of replication lag a delivery will not be found. Rather than raising a Hookshot::BadResponseError,
      # we set delivery to nil so that show.html will know to display a message asking user to try again later.
      @delivery = nil
    else
      raise Hookshot::BadResponseError.new(status)
    end
  end

  def authorized?
    logged_in? && can_view_hook_deliveries?
  end

  def can_view_hook_deliveries?
    return false if installation_target_context && installation_target_context != current_hook.installation_target

    owner = case current_hook.installation_target
    when Repository, Marketplace::Listing, Integration, SponsorsListing
      current_hook.installation_target.owner
    when User, Organization, Business
      current_hook.installation_target
    else
      raise "Unknown hook installation target"
    end

    # user needs to be admin, or site_admin to view hook deliveries
    # additionaly users can be able to view hook deliveries if
    #  - they are granted manage_webhooks FGP over a Repository
    #  - they are granted manage_organization_webhooks FGP over a Organization
    #  both of them are a superset of view_hook_deliveries
    if current_user.user? && current_hook.installation_target.is_a?(Repository)
      current_hook.installation_target.async_can_manage_webhooks?(current_user, site_admin: true).sync
    elsif current_user.user? && current_hook.installation_target.is_a?(Organization)
      owner.async_can_write_org_webhooks?(current_user, site_admin: true).sync
    else
      ::Permissions::Enforcer.authorize(
        action: :view_hook_deliveries,
        actor: current_user,
        subject: current_hook.installation_target,
        context: {
          considers_site_admin: true
        }
      ).allow?
    end
  end

  def hookshot
    @hookshot ||= Hookshot::Client.for_parent current_hook.hookshot_parent_id
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

  def hook_delivery_rate_limit_key
    "hook_deliveries:#{action_name}:#{current_user.id}"
  end

  def hook_delivery_rate_limit_record
    GitHub.dogstats.increment "hook_delivery", tags: ["action:#{action_name}", "error:ratelimited"]
  end

  # Measure payloads and response bodies so we can make a more intelligent
  # decision on where to limit these when displaying them in the UI.
  #
  # https://github.com/github/github/pull/20668
  def gauge_payload_and_response_size
    payload = @delivery.payload
    response_body = @delivery.response_body
    GitHub.dogstats.gauge "hook_delivery.payload_size", payload.to_s.size, tags: ["action:show"]
    GitHub.dogstats.gauge "hook_delivery.response_body_size", response_body.to_s.size, tags: ["action:show"]
  end

  # Allow access to these endpoints from restricted stafftools frontends.

  def ip_allowlist_enforceable
    bypass_conditional_access_policy? ? :no : :yes
  end

  def external_conditional_access_policy_enforceable
    bypass_conditional_access_policy? ? :no : :yes
  end

  def require_active_external_identity_session?
    !bypass_conditional_access_policy?
  end

  def two_factor_enforceable
    bypass_conditional_access_policy? ? :no : :yes
  end

  def bypass_conditional_access_policy?
    GitHub.admin_host? && logged_in? && current_user.site_admin?
  end

  def installation_target_context
    case params[:context]
    when "repository"
      Repository.with_name_with_owner(params[:user_id], params[:repository])
    when "organization"
      Organization.find_by(login: params[:organization_id])
    when "enterprise"
      Business.find_by(slug: params[:slug])
    when "user_integration"
      current_user.integrations.not_marked_for_deletion.find_by!(slug: params[:app_id])
    when "org_integration"
      org = Organization.find_by(login: params[:organization_id])
      org && org.integrations.not_marked_for_deletion.find_by!(slug: params[:app_id])
    when "marketplace_listing"
      Marketplace::Listing.find_by(slug: params[:listing_slug])
    when "sponsors_listing"
      User.find_by(login: params[:sponsorable_id])&.sponsors_listing
    end
  end
end
