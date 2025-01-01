# typed: true
# frozen_string_literal: true

class ProfilePinsController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    only: [:pinnable_items]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    only: [:pinned_items_modal]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:pinnable_items, :pinned_items_modal], optional: true

  PINNABLE_ITEMS_LIMIT_ORG = 500
  PINNABLE_ITEMS_LIMIT_USER = 250

  include UserContributionsHelper

  before_action :login_required, only: %w(reorder_pinned_items pinned_items_modal set_pinned_items)
  before_action :ensure_user_exists,
    only: %w(pinned_items_modal reorder_pinned_items set_pinned_items pinnable_items)

  def pinnable_items # rubocop:todo GitHub/UseRestfulActions
    return head(:forbidden) unless this_user.can_pin_profile_items?(current_user)

    respond_to do |format|
      format.html do
        render(
          partial: "profile_pins/pinnable_items",
          locals: {
            pinnable_items: fetch_pinnable_items(viewing_as_member: viewing_as_member?),
            pinned_items: this_user.pinned_items(viewer: current_user, internal_view: viewing_as_member?),
            pinned_items_remaining: this_user.pinned_items_remaining(internal_view: viewing_as_member?),
            view_as: params["view_as"],
            viewing_page_as_member: viewing_as_member?,
            dialog_location: params["dialog_location"]
          }
        )
      end
    end
  end

  def reorder_pinned_items # rubocop:todo GitHub/UseRestfulActions
    return head(:forbidden) unless this_user.can_pin_profile_items?(current_user)

    pinned_items = get_pinned_items_from_id_and_type(pinned_items_id_and_type: params[:pinned_items_id_and_type])
    this_user.profile&.reorder_pinned_items(pinned_items, internal_view: viewing_as_member?)

    render(
      partial: "profile_pins/pinned_items",
      locals: {
        pinned_items: this_user.pinned_items(viewer: current_user, internal_view: viewing_as_member?),
        profile_owner: this_user,
        viewer_can_change_pinned_items: this_user.can_pin_profile_items?(current_user),
      }
    )
  end

  def pinned_items_modal # rubocop:todo GitHub/UseRestfulActions
    return head(:forbidden) unless this_user.can_pin_profile_items?(current_user)

    has_pinnable_repos, has_pinnable_gists = Promise.all([
      this_user.async_any_pinnable_items?(types: ["Repository"], internal_view: viewing_as_member?),
      this_user.async_any_pinnable_items?(types: ["Gist"]),
    ]).sync
    respond_to do |format|
      format.html do
        render(
          partial: "profile_pins/pinned_items_modal",
          locals: {
            pinnable_items: fetch_pinnable_items(viewing_as_member: viewing_as_member?),
            pinned_items: this_user.pinned_items(viewer: current_user, internal_view: viewing_as_member?),
            has_pinnable_repos: has_pinnable_repos,
            has_pinnable_gists: has_pinnable_gists,
            view_as: params["view_as"],
            viewing_page_as_member: viewing_as_member?,
            modal_description_copy: modal_description_copy,
            dialog_location: params["dialog_location"]
          }
        )
      end
    end
  end

  def set_pinned_items # rubocop:todo GitHub/UseRestfulActions
    return head(:forbidden) unless this_user.can_pin_profile_items?(current_user)

    profile_owner = this_user
    pinned_items = get_pinned_items_from_id_and_type(pinned_items_id_and_type: params[:pinned_items_id_and_type])

    profile = profile_owner.profile
    pinner = ProfilePinner.new(user: profile_owner, items: pinned_items,
                               viewer: current_user, viewing_as_member: viewing_as_member?)
    pinner.async_pin.sync

    pin_count = profile_owner.pinned_items(viewer: current_user, internal_view: viewing_as_member?).count
    profile_owner_is_viewer = profile_owner == current_user

    message = if pin_count < 1
      if profile_owner_is_viewer
        "Your popular repositories will now be shown instead of your pins."
      else
        "No repositories or gists are pinned now."
      end
    else
      subject = if profile_owner_is_viewer
        "Your"
      else
        "#{profile_owner.display_login}’s"
      end
      suffix = pin_count > 1 ? " Drag and drop to reorder them." : nil
      "#{subject} pins have been updated.#{suffix}"
    end

    flash[:notice] = message
    if params[:view_as].present?
      redirect_to user_path(profile_owner.display_login, params: { view_as: params["view_as"] })
    else
      redirect_to user_path(profile_owner.display_login)
    end
  end

  private

  # Ensure the user specified via the login in the URL is a real User or Organization.
  def ensure_user_exists
    return if this_user

    if request.xhr?
      head :not_found
    else
      render_404
    end
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_user # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_user
  end

  def fetch_pinnable_items(viewing_as_member: false)
    @_pinnable_items ||= begin
      pinner = ProfilePinner.new(user: this_user, viewer: current_user, viewing_as_member: viewing_as_member)
      items = pinner.async_sorted_pinnable_items(types: %w[Repository Gist]).sync

      pinnable_items_limit = this_user.user? ? PINNABLE_ITEMS_LIMIT_USER : PINNABLE_ITEMS_LIMIT_ORG
      GitHub::SimplePagination.paginate_collection(items, per_page: pinnable_items_limit, page: current_page)
    end
  end

  # Accepts an array of concatenated id-type values, parses them,
  # evaluates `find` calls for corresponding ActiveRecord models (such as Repository or Gist),
  # and returns ActiveRecord entities.
  #
  # Given ["1-Repository", "2-Repository"]
  # Returns #<Repository id: 2 ...>, <Repository id: 1 ...>
  def get_pinned_items_from_id_and_type(pinned_items_id_and_type:)
    pinned_items = []
    return pinned_items unless pinned_items_id_and_type.present?

    order = []
    pinned_items_hash = {}
    hash_of_ids_by_type = pinned_items_id_and_type.each_with_object({}) do |str, hash|
      id, name = str.split("-")
      next unless %w[Repository Gist].include?(name)
      hash[name] ||= []
      hash[name] << id.to_i
      order << name
    end

    hash_of_ids_by_type.each do |type, ids_for_type|
      pinned_items_hash[type] = type.constantize.find(ids_for_type)
    end

    order.each do |item_type|
      pinned_items.push(pinned_items_hash[item_type].shift)
    end

    pinned_items
  end


  memoize def viewing_as_member?
    this_user.organization? && params["view_as"] == "member" && this_user.member?(current_user)
  end

  def modal_description_copy
    prefix = "Select up to six"

    if viewing_as_member?
      suffix = "you'd like to show only to members of the organization."
    else
      suffix = "you'd like to show to anyone."
    end

    if this_user.organization? && this_user.enterprise_managed_user_enabled?
      "#{prefix} repositories #{suffix}"
    elsif viewing_as_member?
      "#{prefix} public, internal, or private repositories #{suffix}"
    else
      "#{prefix} public repositories#{this_user.user? ? " or gists" : ""} #{suffix}"
    end
  end
end
