# typed: true
# frozen_string_literal: true

class Codespaces::UnauthorizedOrganizationsComponent < ApplicationComponent

  attr_reader :classes, :cap_filter, :resource_label

  def initialize(classes:, cap_filter:, current_repository: nil, billable_owner: nil, resource_label: "codespaces")
    @classes = classes
    @cap_filter = cap_filter
    @current_repository = current_repository
    @billable_owner = billable_owner
    @resource_label = resource_label
  end

  def render?
    if @billable_owner.present?
      !@billable_owner.user?
    else
      @current_repository.present? || logged_in?
    end
  end

  def codespaces_orgs
    orgs.select { |org| !org.codespaces_access_disabled? }
  end

  def orgs
    if @billable_owner
      [@billable_owner]
    else
      current_user.organizations
    end
  end
end
