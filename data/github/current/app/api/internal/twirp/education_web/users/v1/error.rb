# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::EducationWeb::Users::V1::Error
  module Messages
    FF_DISABLED = "FF not enabled"
    REPOSITORY_NOT_FOUND = "Repository not found"
    REPOSITORY_NOT_PUBLIC = "Repository not public."
    INVALID_ACTION_TYPE = "Invalid action type."
    USER_NOT_FOUND = "User not found."
    CAN_NOT_STAR = "User can not star this repository."
    CAN_NOT_UNSTAR = "User can not unstar this repository."
  end
end
