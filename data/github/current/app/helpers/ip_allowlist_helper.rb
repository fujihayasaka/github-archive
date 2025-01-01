# typed: true
# frozen_string_literal: true

module IpAllowlistHelper
  include ActionView::Helpers::TagHelper

  extend T::Helpers
  requires_ancestor { ApplicationController }

  # Public: Returns the HTML hint that's used when a request comes from an IP
  # that is not allowed to access an account, and we want to tell the user that
  # they need to connect from an allowed IP address to access the resource.
  #
  # target - An Organization or Business representing the owner of an IP allow list.
  # text - A String describing the action being attempted by the user.
  # join_word - A String to join the text argument with the text representation of the target.
  #
  # Returns String.
  def restricted_ip_allowlist_target_hint(target, text: "", join_word: "within")
    safe_join([
      "Connect from an allowed IP address",
      text,
      (target.is_a?(Business) ? "for accounts #{join_word} the" : "#{join_word} the"),
      content_tag(:strong, target.is_a?(Business) ? target.name : target.display_login),
      (target.is_a?(Business) ? "enterprise." : "organization."),
    ], " ")
  end

  # Public: Return the IP allow list entries for an inferred target.
  #
  # May be used within the context of a request to get the IP allow list
  # entries on a target that is inferred from the request context. Currently
  # supports targets found via `this_business` and `this_organization`.
  #
  # Raises RuntimeError if the target cannot be inferred from the request
  # context.
  #
  # Returns ActiveRecord::AssociationRelation
  def ip_allowlist_entries
    target_for_entries
      .filtered_ip_allowlist_entries(query: params[:query])
      .paginate(page: current_page)
  end

  # Public: Return the IP allow list entries for installed GitHub Apps on an
  # inferred target.
  #
  # May be used within the context of a request to get the IP allow list
  # entries for installed GitHub Apps on a target that is inferred from the
  # request context. Currently supports targets found via `this_business`
  # and `this_organization`.
  #
  # Raises RuntimeError if the target cannot be inferred from the request
  # context.
  #
  # Returns ActiveRecord::AssociationRelation
  def installed_app_ip_allowlist_entries
    target_for_entries
      .filtered_installed_app_ip_allowlist_entries(query: params[:query])
      .paginate(page: current_page)
  end

  private

  def target_for_entries
    if defined?(this_business) && T.unsafe(self).this_business.present?
      T.unsafe(self).this_business
    elsif defined?(this_organization) && T.unsafe(self).this_organization.present?
      T.unsafe(self).this_organization
    else
      raise "Could not determine target for ip_allowlist_entries helper method"
    end
  end
end
