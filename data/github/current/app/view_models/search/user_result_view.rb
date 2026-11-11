# typed: true
# frozen_string_literal: true

module Search
  class UserResultView
    include ActionView::Helpers::TagHelper
    include ActionView::Helpers::UrlHelper
    include ApplicationHelper
    include UsersHelper

    attr_reader :id, :display_login, :name, :location, :repos, :followers, :language, :user, :is_current_user, :followed_by_current_user

    # Create a new UserResultView from a `user` document hash returned from
    # the ElasticSearch index.
    #
    # hash - Document Hash returned by ElasticSearch
    #
    def initialize(hash)
      @id   = hash["_id"]
      @user = hash["_model"]

      source = hash["_source"]

      @display_login = @user&.display_login
      @login     = source["login"]
      @name      = source["name"]
      @location  = source["location"]
      @repos     = source["repos"]
      @followers = source["followers"]
      @language  = Search.language_name_from_id(source["language_id"])
      @profile_bio = source["profile_bio"]
      @sponsorable = source["sponsorable"]

      @highlights = hash["highlight"]
    end

    def sponsorable?
      @sponsorable
    end

    # Returns the user's gravatar email as a String.
    def gravatar_email
      user.gravatar_email
    end

    # Returns the user's profile email, if any, taking into account the user's
    # email privacy preferences.
    #
    # logged_in - is the current viewing user logged in? Users are required to
    #             log in to see another user's email, unless in Enterprise
    def email(logged_in: false)
      user.publicly_visible_email(logged_in: logged_in)
    end

    def profile_bio
      return unless @user.profile
      @user.profile.bio
    end

    # Returns true if there are highlight fragments for this user. The
    # highlight fragments contain text from the various user fields with the
    # relevant search terms surrounded by <em> tags.
    def highlights?
      !@highlights.nil?
    end

    # Return the user login. The login may or may not contain highlight tags,
    # but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped login String.
    def hl_login
      return @hl_login if defined? @hl_login
      @hl_login =
          if GitHub.multi_tenant_enterprise?
            ERB::Util.force_escape(@display_login)
          elsif highlights? && (@highlights.key?("login") || @highlights.key?("login.ngram"))
            (@highlights["login"] || @highlights["login.ngram"]).first
          else
            ERB::Util.force_escape(@display_login)
          end
    end

    # Return the user name. The name may or may not contain highlight tags,
    # but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped name String.
    def hl_name
      return @hl_name if defined? @hl_name

      @hl_name =
          if highlights? && @highlights.key?("name")
            @highlights["name"].first
          else
            ERB::Util.force_escape(@name.to_s)
          end
    end

    # Return the profile bio.
    #
    # Returns a String.
    def hl_profile_bio
      return @hl_profile_bio if defined? @hl_profile_bio

      @hl_profile_bio =
        if highlights? && @highlights.key?("profile_bio")
          @highlights["profile_bio"].first
        else
          ERB::Util.force_escape(@profile_bio || "")
        end
    end

    # Populate the object with data needed by the search react app
    def populate_results_data(current_user, followed_by_current_user)
      @avatar_url = @user.primary_avatar_url(80)
      @followed_by_current_user = followed_by_current_user
      @is_current_user = current_user&.login == @login

      # scrub user object because it contains a ton of unnecessary data including secrets
      @user = nil

      hl_name
      hl_profile_bio
      hl_login
    end

    def for_frontend_rendering
      {
        avatar_url: @avatar_url,
        hl_login: @hl_login,
        hl_name: @hl_name,
        hl_profile_bio: @hl_profile_bio,
        followed_by_current_user: @followed_by_current_user,
        followers: @followers,
        id: @id,
        is_current_user: @is_current_user,
        location: @location,
        login: @login,
        display_login: @display_login,
        name: @name,
        profile_bio: @profile_bio,
        sponsorable: @sponsorable,
        repos: @repos,
      }
    end


  end  # UserResultView
end  # Search
