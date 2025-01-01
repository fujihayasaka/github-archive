# typed: true
# frozen_string_literal: true

module Users
  class AvatarListComponent < ApplicationComponent
    include AvatarHelper

    renders_one :truncator

    # Public: Initialize an AvatarList.
    #
    # users - array of User objects or Hashes containing user attributes
    # show_as_grid - whether to display as a grid instead of a vertical list
    # show_names_summary - whether to display a summary string of usernames
    def initialize(users, show_as_grid: true, show_names_summary: false, data: {})
      @show_as_grid = show_as_grid
      @show_names_summary = show_names_summary

      @user_hashes = users
      @data = data
      if users[0]&.is_a?(User)
        @user_hashes = users.map do |u|
          {
            avatar_url: u.primary_avatar_url(64),
            login: u.display_login,
            profile_name: u.profile_name,
            profile_url: u.permalink,
            avatar_user_actor: avatar_user_actor?(u)
          }
        end
      end
    end

    attr_reader :show_as_grid, :show_names_summary, :data

    # Example: "monalisa1, monalisa2, and 2 other users"
    def user_names_summary
      return "" unless @user_hashes.count > 0

      names = @user_hashes.take(2).pluck(:login)
      remaining_count = @user_hashes.count - names.count

      if remaining_count == 1
        # if there's only one more user, just include everyone's name
        names << @user_hashes.third[:login]
      elsif remaining_count > 1
        names << "#{remaining_count} other contributors"
      end

      names.to_sentence
    end

    # These attributes add the user hovercard when added to an element
    def user_hovercard_attributes(login)
      safe_data_attributes(hovercard_data_attributes_for_user_login(login))
    end
  end
end
