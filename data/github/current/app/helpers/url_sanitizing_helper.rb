# typed: true
# frozen_string_literal: true

module UrlSanitizingHelper
  extend T::Sig
  extend T::Helpers
  include ActionView::Helpers::TagHelper

  # When users view private repos, we don't want to leak the repo name, owner,
  # or file paths to Google Analytics, so we substitute an anonymized path.
  #
  # Returns only the path as a string.
  def analytics_location
    T.bind(self, T.untyped)
    if flash[:analytics_location].present?
      flash[:analytics_location]
    elsif current_repository
      "/<user-name>/<repo-name>/#{params[:controller]}/#{params[:action]}"
    elsif (org = current_organization || current_organization_for_member_or_billing) && org.display_login.present?
      request.path.sub(%r{\A/(organizations/|orgs/)?#{Regexp.escape(org.display_login)}(/|\Z)}i, '/\1<org-login>\2')
    elsif gist_request?
      masked_gist_location
    elsif params[:controller].in?(%w(profiles users)) && params[:user_id] && (user = this_user) && user.display_login.present?
      request.path.sub(%r{\A/#{Regexp.escape(user.display_login)}(/|\Z)}i, '/<user-name>\1')
    else
      request.path
    end
  end

  # When users view private repos, we don't want to leak the repo name, owner,
  # or file paths to Google Analytics, so we substitute an anonymized path.
  #
  # Returns an HTML meta tag.
  def analytics_location_meta_tag
    T.bind(self, T.untyped)
    tags = []
    if extra_params = flash[:analytics_location_params]
      tags << tag(:meta,
          :name => "analytics-location-params",
          :content => extra_params.to_query,
          "data-turbo-transient" => true,
      )
    end

    if flash[:analytics_location_query_strip] == "true"
      tags << tag(:meta,
        :name => "analytics-location-query-strip",
        :content => "true",
        "data-turbo-transient" => "true",
      )
    end

    custom_url = if flash[:analytics_location].present?
      flash[:analytics_location]
    elsif current_repository
      "/<user-name>/<repo-name>/#{params[:controller]}/#{params[:action]}"
    elsif (org = current_organization || current_organization_for_member_or_billing) && org.display_login.present?
      request.path.sub(%r{\A/(organizations/|orgs/)?#{Regexp.escape(org.display_login)}(/|\Z)}i, '/\1<org-login>\2')
    elsif gist_request?
      masked_gist_location
    elsif params[:controller].in?(%w(profiles users)) && params[:user_id] && (user = this_user) && user.display_login.present?
      request.path.sub(%r{\A/#{Regexp.escape(user.display_login)}(/|\Z)}i, '/<user-name>\1')
    end

    if custom_url
      tags << tag(:meta,
          :name => "analytics-location",
          :content => custom_url,
          "data-turbo-transient" => true,
      )
    end

    octolytics_path = if flash[:override_octolytics_location]
      if custom_url
        custom_url
      elsif flash[:analytics_location_query_strip] == "true"
        request.path
      end
    end

    if octolytics_path
      tags << tag(:meta,
        :name => "octolytics-location",
        :content => octolytics_path,
        "data-turbo-transient" => true,
      )
    end

    safe_join(tags)
  end

  # Internal: Retuns the current path with the username and gist id
  # masked.
  #
  # Example:
  #
  #   /jdpace/a6be29075f1917339319/edit => /<user-name>/<gist-id>/edit
  #
  # Returns a String.
  def masked_gist_location
    T.bind(self, T.untyped)
    request.path.dup.tap do |gist_location|
      gist_location.sub! params[:user_id], "<user-name>" if params[:user_id]
      gist_location.sub! params[:gist_id], "<gist-id>" if params[:gist_id]
    end
  end
end
