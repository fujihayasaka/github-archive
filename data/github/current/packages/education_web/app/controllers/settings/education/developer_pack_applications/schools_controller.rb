# typed: strict
# frozen_string_literal: true

class Settings::Education::DeveloperPackApplications::SchoolsController < ApplicationController
  include Settings::ControllerMethods
  include Settings::Education::DeveloperPackApplications::SharedControllerMethods

  MINIMUM_SCHOOL_NAME_QUERY_LENGTH = 3

  depends_on_clusters(
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    only: [:index],
  )

  before_action :require_minimum_school_name_query_length

  sig { void }
  def index
    headers["Cache-Control"] = "no-cache, no-store"

    respond_to do |format|
      format.html_fragment do
        render(
          Education::DeveloperPackApplication::AutoCompleteSchoolsComponent.new(
            schools:,
            user_has_two_factor_auth_enabled: current_user.two_factor_authentication_enabled?,
            user_verified_emails: current_user.emails.verified.pluck(:email),
          ),
          layout: false,
        )
      end
    end
  end

  private

  sig { returns(T.untyped) }
  def schools
    results = schools_client.search_schools(school_name_query: params[:q], ip_address: request.remote_ip)

    if results.data && results.error.nil?
      results.data["schools"] || []
    else
      []
    end
  end

  sig { void }
  def require_minimum_school_name_query_length
    head 200 if params[:q].length < MINIMUM_SCHOOL_NAME_QUERY_LENGTH
  end
end
