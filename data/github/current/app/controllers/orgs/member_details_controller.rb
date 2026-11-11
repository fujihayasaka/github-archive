# typed: true
# frozen_string_literal: true

class Orgs::MemberDetailsController < Orgs::Controller
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::MemberDetailsController#index",
  ]

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Ballast,
    ApplicationRecord::Iam,
    only: %i(index)

  include EnterpriseManagedUsersHelper

  def index
    keyed_contents = ActiveRecord::Base.connected_to(role: :reading) do
      keyed_objects = keyed_details_from_items(items)
      keyed_objects.each_with_object({}) do |(key, details), contents|
        contents[key] = render_member_details(details)
      end
    end

    respond_to do |wants|
      wants.json do
        render json: keyed_contents
      end
    end
  rescue ActionController::ParameterMissing
    head :bad_request
  end

  private

  # Expects params as follows:
  #
  # params[:items] = {
  #   item-0: { member_id: ID, only_should_show_guest_collaborators: BOOL },
  #   item-1: { member_id: ID, only_should_show_guest_collaborators: BOOL },
  #   ...
  # }
  memoize def items
    if params[:items].instance_of?(ActionController::Parameters)
      params.require(:items).permit!.to_h
    else
      raise ActionController::ParameterMissing.new(:items)
    end
  end

  memoize def member_ids
    items.values.map { |item| item[:member_id]&.to_i }.compact.uniq
  end

  def keyed_details_from_items(items)
    details_by_member_id = \
      this_organization.visible_users_for(current_user)
        .where(id: member_ids).each_with_object({}) do |member, details|
        details[member.id] = {
          member: member,
          only_should_show_guest_collaborators: only_should_show_guest_collaborators?(member.id)
        }
      end

    items.transform_values do |member_params|
      details_by_member_id[member_params[:member_id]&.to_i]
    end
  end

  def render_member_details(details)
    return "" unless details.present?

    view = create_view_model(
      Orgs::People::MemberView,
      member: details[:member],
      organization: this_organization,
      eligible_domain_emails: eligible_domain_emails_for_members[details[:member].id] || []
    )
    render_to_string(
      partial: "orgs/members/list_item_details",
      formats: [:html],
      locals: {
        view: view,
        only_should_show_guest_collaborators: details[:only_should_show_guest_collaborators]
      }
    )
  end

  def only_should_show_guest_collaborators?(member_id)
    if item = items.values.find { |item| item[:member_id]&.to_i == member_id }
      return item[:only_should_show_guest_collaborators] == "true"
    end

    false
  end

  # Private: Returns a Hash of admin viewable organization member IDs and an
  # Array of their emails. Verified or approved domains considered for
  # GHES, while only verified domains considered for dotcom.
  #
  # Returns a Hash{Integer => Array[UserEmail]}
  memoize def eligible_domain_emails_for_members
    return {} unless this_organization.adminable_by?(current_user)
    this_organization.domain_emails_for_member_ids(member_ids: member_ids)
  end
end
