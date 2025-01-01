# typed: true
# frozen_string_literal: true

class PersonalAccessTokens::IndexListItemComponent < ApplicationComponent
  attr_reader :access, :flash, :page

  delegate :id, :name, :grant, :grant_request, :has_requested_grant?, to: :access

  def initialize(access, flash, **opts)
    @access = access
    @flash = flash
    @page = opts[:page] || 1
  end

  def actor
    @access.active_request_or_grant&.target || User.ghost
  end

  def resource_owner_message
    return "Access for public resources only" if actor.ghost?

    "Access for resources belonging to #{actor.display_login}"
  end

  def newly_created?
    new_access["id"] == id
  end

  def successfully_created?
    !!new_access["success"]
  end

  def unhashed_token
    new_access["token"]
  end

  private

  def new_access
    flash[:new_access] || {}
  end
end
