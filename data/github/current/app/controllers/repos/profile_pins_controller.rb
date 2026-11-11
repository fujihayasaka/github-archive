# typed: true
# frozen_string_literal: true

class Repos::ProfilePinsController < AbstractRepositoryController

  before_action :require_profile_pin_access
  before_action :require_profile_owner_is_viewer, only: %w(create destroy)

  def create
    if owner.pinned_items_remaining == 0
      error_message_subject = profile_owner_is_viewer? ? "Profile" : "Public"
      flash[:error] = "#{error_message_subject} pins are full. Please unpin some items before adding more."
      redirect_to :back and return
    end

    pinned_items = owner.profile_pins.includes(:pinned_item).order(:position).map(&:pinned_item)
    pinned_items << current_repository

    profile_pinner = ProfilePinner.new(user: owner, viewer: current_user, items: pinned_items)
    profile_pinner.async_pin.sync

    flash_and_redirect
  end

  def destroy
    ProfilePinner.unpin(current_repository, user: owner, viewer: current_user)

    flash_and_redirect
  end

  def pin_organization_repo # rubocop:todo GitHub/UseRestfulActions
    if params["public-profile"] == "on" && !owner.pinned_repository?(current_repository)
      if owner.pinned_items_remaining == 0
        flash[:error] = "Public pins are full. Please unpin some items before adding more."
        redirect_to :back and return
      end
      ProfilePinner.pin(current_repository, user: owner, viewer: current_user, internal_view: false)
    elsif params["public-profile"] == "off"
      ProfilePinner.unpin(current_repository, user: owner, viewer: current_user, internal_view: false)
    end

    if params["internal-profile"] == "on" && !owner.pinned_repository?(current_repository, internal_view: true)
      if owner.pinned_items_remaining(internal_view: true) == 0
        flash[:error] = "Members-only pins are full. Please unpin some items before adding more."
        redirect_to :back and return
      end
      ProfilePinner.pin(current_repository, user: owner, viewer: current_user, internal_view: true)
    elsif params["internal-profile"] == "off"
      ProfilePinner.unpin(current_repository, user: owner, viewer: current_user, internal_view: true)
    end

    if params["user-profile"] == "on" && !current_user.pinned_repository?(current_repository)
      if current_user.pinned_items_remaining == 0
        flash[:error] = "Profile pins are full. Please unpin some items before adding more."
        redirect_to :back and return
      end
      ProfilePinner.pin(current_repository, user: current_user, viewer: current_user)
    elsif params["user-profile"] == "off"
      ProfilePinner.unpin(current_repository, user: current_user, viewer: current_user)
    end

    flash[:notice] = "Your pins have been updated."
    redirect_to :back
  end

  private

  def flash_and_redirect
    pin_count = owner.profile_pins.count

    message = if pin_count < 1
      if profile_owner_is_viewer?
        "Your popular repositories will now be shown instead of your pins."
      else
        "No repositories or gists are pinned now."
      end
    else
      subject = if profile_owner_is_viewer?
        "Your"
      else
        "#{owner.display_login}’s"
      end
      suffix = pin_count > 1 ? " Drag and drop to reorder them." : nil
      "#{subject} pins have been updated.#{suffix}"
    end

    flash[:notice] = message
    if profile_owner_is_viewer?
      redirect_to user_path(owner)
    else
      redirect_to user_path(owner, params: { view_as: "public" })
    end
  end

  def profile_owner_is_viewer?
    owner == current_user
  end

  def require_profile_pin_access
    if !params["user-profile"].blank? && params["internal-profile"].blank? && params["public-profile"].blank?
      render_404 unless current_repository.contributor_of_any_kind?(current_user)
    else
      render_404 unless owner.can_pin_profile_items?(current_user)
    end
  end

  def require_profile_owner_is_viewer
    render_404 unless profile_owner_is_viewer?
  end
end
