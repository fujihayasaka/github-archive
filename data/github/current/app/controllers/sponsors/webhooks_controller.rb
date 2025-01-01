# typed: strict
# frozen_string_literal: true

class Sponsors::WebhooksController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  before_action :require_acceptance_into_sponsors_program
  before_action :non_waitlisted_sponsors_listing_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:edit, :new, :index], optional: true

  stylesheet_bundle :sponsors

  sig { void }
  def index
    sponsors_listing = T.must_because(sponsorable_sponsors_listing) do
      "required by `non_waitlisted_sponsors_listing_required` filter"
    end

    hooks = Hook::StatusLoader.load_statuses(
      hook_records: sponsors_listing.hooks,
      parent: sponsors_listing,
    )

    render "sponsors/webhooks/index", locals: {
      sponsors_listing: sponsorable_sponsors_listing,
      hooks: hooks,
    }
  end

  sig { void }
  def new
    sponsors_listing = T.must_because(sponsorable_sponsors_listing) do
      "required by `non_waitlisted_sponsors_listing_required` filter"
    end

    render "sponsors/webhooks/new", locals: {
      sponsors_listing: sponsors_listing,
      hook: sponsors_listing.hooks.build(active: true),
    }
  end

  sig { void }
  def create
    sponsors_listing = T.must_because(sponsorable_sponsors_listing) do
      "required by `non_waitlisted_sponsors_listing_required` filter"
    end

    hook = sponsors_listing.hooks.build(name: "web", events: [Hook::WildcardEvent])
    hook.track_creator(current_user)

    if hook.update(hook_params)
      flash[:notice] = "Okay, that hook was successfully created. We sent a ping payload to test it out! Read more about it at #{GitHub.developer_help_url}/webhooks/#ping-event."
      redirect_to sponsorable_dashboard_webhooks_path
    else
      render "sponsors/webhooks/new", locals: {
        sponsors_listing: sponsorable_sponsors_listing,
        hook: hook,
      }
    end
  end

  sig { void }
  def edit
    sponsors_listing = T.must_because(sponsorable_sponsors_listing) do
      "required by `non_waitlisted_sponsors_listing_required` filter"
    end

    render "sponsors/webhooks/edit", locals: {
      sponsors_listing: sponsors_listing,
      hook: sponsors_listing.hooks.find(params[:id]),
    }
  end

  sig { void }
  def update
    sponsors_listing = T.must_because(sponsorable_sponsors_listing) do
      "required by `non_waitlisted_sponsors_listing_required` filter"
    end

    hook = sponsors_listing.hooks.find(params[:id])

    if hook.update(hook_params)
      flash[:notice] = "Okay, the hook was successfully updated."
      redirect_to sponsorable_dashboard_webhooks_path
    else
      render "sponsors/webhooks/edit", locals: {
        sponsors_listing: sponsorable_sponsors_listing,
        hook: hook,
      }
    end
  end

  sig { void }
  def destroy
    sponsors_listing = T.must_because(sponsorable_sponsors_listing) do
      "required by `non_waitlisted_sponsors_listing_required` filter"
    end

    hook = sponsors_listing.hooks.find(params[:id])

    if hook.destroy
      flash[:notice] = "Okay, the hook was successfully deleted."
      redirect_to sponsorable_dashboard_webhooks_path
    else
      flash[:error] = "There was an error deleting your hook: #{hook.errors.full_messages.to_sentence}"
      redirect_to :back
    end
  end

  private

  sig { returns(ActionController::Parameters) }
  def hook_params
    params.require(:hook).permit(
      :active,
      :content_type,
      :secret,
      :url,
    )
  end

  sig { returns(T.any(Symbol, GitHubSponsors::Types::Sponsorable)) }
  def target_for_conditional_access
    target_sponsorable = sponsorable
    return :no_target_for_conditional_access unless target_sponsorable # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    target_sponsorable
  end
end
