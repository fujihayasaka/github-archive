# typed: true
# frozen_string_literal: true

# Public: Link to a user or organization's profile page. Defaults to making the login the link text. Includes
# the user hovercard.
class Users::ProfileLinkComponent < Primer::Component
  include HovercardHelper

  # user - User or Organization; required if `login` and `is_organization` are not given
  # login - the String login for the User or Organization whose profile should be linked to; only required if
  #         `user` is not given
  # is_organization - Boolean indicating whether the given login represents an Organization, as opposed to a User;
  #                   only required if `user` is not given
  def initialize(user: nil, login: nil, is_organization: nil, **system_arguments)
    @user = user
    @login = login || user&.display_login
    @is_organization = is_organization
    @is_organization = user&.organization? if @is_organization.nil?
    @system_arguments = system_arguments
    @system_arguments[:display] ||= :inline_block
    @system_arguments[:data] ||= {}
  end

  def call
    # this is safe for this rubocop rule since it refers to the login attribute in this class which already defers to display_login or the passed value
    @system_arguments[:href] ||= user_path(user || login) # rubocop:disable GitHub/DoNotAllowLogin
    @system_arguments[:data].merge!(hovercard_data_attributes)
    render(Primer::Beta::Link.new(**@system_arguments)) do
      # this is safe for this rubocop rule since it refers to the login attribute in this class which already defers to display_login or the passed value
      content.presence || login # rubocop:disable GitHub/DoNotAllowLogin
    end
  end

  private

  attr_reader :login, :user

  def render?
    # this is safe for this rubocop rule since it refers to the login attribute in this class which already defers to display_login or the passed value
    login.present? && !@is_organization.nil? # rubocop:disable GitHub/DoNotAllowLogin
  end

  def organization?
    !!@is_organization
  end

  def hovercard_data_attributes
    if organization?
      # this is safe for this rubocop rule since it refers to the login attribute in this class which already defers to display_login or the passed value
      hovercard_data_attributes_for_org(login: login) # rubocop:disable GitHub/DoNotAllowLogin
    else
      # this is safe for this rubocop rule since it refers to the login attribute in this class which already defers to display_login or the passed value
      hovercard_data_attributes_for_user_login(login) # rubocop:disable GitHub/DoNotAllowLogin
    end
  end
end
