# typed: true
# frozen_string_literal: true

class Sponsors::SponsorableCardComponent < ApplicationComponent
  include HovercardHelper
  include UsersHelper

  # login - String login of the User or Organization who can be sponsored
  # avatar_url - String URL for the sponsorable User or Organization's avatar
  # avatar_classes - optional String list of CSS classes to apply to the `img` tag for the sponsorable's avatar
  # hovercard_data - optional Hash of data to apply to links to the sponsorable's profile
  # repo_id - optional Integer ID for the Repository being shown, if any
  # repo_name - optional String name of the Repository being shown, if any
  # repo_url - optional String URL for the Repository being shown, if any
  # description - optional String description of the Repository being shown, if any
  # star_count - optional Integer number of stars the Repository has, if a repo is being shown
  # is_sponsoring - Boolean indicating whether the viewer is sponsoring the sponsorable
  # sponsor_button_location - optional Symbol describing where this component is being displayed, for use in
  #                           Hydro click tracking; defaults to unknown
  # sponsor_login - optional String login of a User or Organization who is currently sponsoring the sponsorable,
  #                 to display as an example; should be one who the viewer is allowed to know is a sponsor, based
  #                 on sponsorship visibility
  # sponsor_hovercard_data - optional Hash of data to apply to links to the profile page of `sponsor_login`
  # sponsor_avatar_url - optional String URL for the avatar of `sponsor_login`
  # sponsor_avatar_classes - optional String list of CSS classes to apply to the `img` tag for the `sponsor_login`'s
  #                          avatar
  # total_sponsors - Integer representing how many sponsors the sponsorable currently has
  # total_org_sponsors - Integer representing how many organizations have sponsored the sponsorable
  # primary_language - String name of the programming language that the `repo_name` repository is written in, if a
  #                    repository is being shown
  # repository_count - Integer number of dependencies the `login_to_sponsor_as` user/org has that are represented by
  #                    the sponsorable being shown
  # active_goal - SponsorsGoal object representing the sponsorable's active sponsorship goal
  # filter_set - optional SponsorsExploreFilterSet for use in links, to preserve existing filters and sort order
  # login_to_sponsor_as - optional String User or Organization login to use as the `sponsor` URL parameter when
  #                       linking to the Sponsors profile page; if omitted, the Sponsors profile will default to
  #                       the current user as the potential sponsor
  def initialize(
    login:,
    avatar_url:,
    avatar_classes: "",
    hovercard_data: {},
    repo_id: nil,
    repo_name: nil,
    repo_url: nil,
    description: nil,
    star_count: 0,
    is_sponsoring: false,
    sponsor_button_location: nil,
    sponsor_login: nil,
    sponsor_hovercard_data: {},
    sponsor_avatar_url: nil,
    sponsor_avatar_classes: nil,
    total_sponsors: 0,
    total_org_sponsors: 0,
    primary_language: nil,
    repository_count: nil,
    active_goal: nil,
    filter_set: nil,
    login_to_sponsor_as: nil
  )
    @login = login
    @avatar_url = avatar_url
    @avatar_classes = avatar_classes
    @hovercard_data = hovercard_data
    @repo_id = repo_id
    @repo_name = repo_name
    @repo_url = repo_url
    @description = description
    @star_count = star_count
    @is_sponsoring = is_sponsoring
    @sponsor_button_location = sponsor_button_location
    @sponsor_login = sponsor_login
    @sponsor_hovercard_data = sponsor_hovercard_data
    @sponsor_avatar_url = sponsor_avatar_url
    @sponsor_avatar_classes = sponsor_avatar_classes
    @total_sponsors = total_sponsors
    @total_org_sponsors = total_org_sponsors
    @remaining_sponsor_count = @total_sponsors - 1
    @primary_language = primary_language
    @repository_count = repository_count
    @active_goal = active_goal
    @filter_set = filter_set || SponsorsExploreFilterSet.new
    @login_to_sponsor_as = login_to_sponsor_as
  end

  private

  attr_reader :filter_set, :login_to_sponsor_as

  def repo?
    @repo_name.present? && @repo_url.present?
  end

  def sponsor?
    @sponsor_login.present? && @sponsor_avatar_url.present?
  end

  # Private: Check if the user/org who would become the sponsor, should the viewer click a 'Sponsor' button on the
  # page, is the viewer themselves.
  #
  # Returns a Boolean.
  def would_personally_sponsor?
    return false unless logged_in?
    filter_set.account_login.blank? || filter_set.account_login == current_user.login
  end

  def repo_count_subject_and_verb(capitalize:)
    if would_personally_sponsor?
      first_letter = capitalize ? "Y" : "y"
      "#{first_letter}ou depend on"
    else
      "#{filter_set.account_login} depends on"
    end
  end

  memoize def repo_count_phrase
    units = "repository".pluralize(@repository_count)
    "#{social_count(@repository_count)} #{units} they own or maintain"
  end
end
