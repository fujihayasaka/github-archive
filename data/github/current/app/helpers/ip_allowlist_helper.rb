# typed: true
# frozen_string_literal: true

module IpAllowlistHelper
  include ActionView::Helpers::TagHelper

  extend T::Helpers
  requires_ancestor { ApplicationController }

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
