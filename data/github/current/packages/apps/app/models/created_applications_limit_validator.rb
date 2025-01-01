# typed: true
# frozen_string_literal: true

class CreatedApplicationsLimitValidator < ActiveModel::Validator
  USER_HAS_CREATED_TOO_MANY_APPS_MESSAGE = "You can't create any more applications".freeze

  # application should be an instance of OauthApplication or Integration
  def validate(application)
    return unless application.user.present?

    user = application.user
    if user.reached_applications_creation_limit?(application_type: application.class)
      application.errors.add(:"user", USER_HAS_CREATED_TOO_MANY_APPS_MESSAGE)
    end
  end
end
