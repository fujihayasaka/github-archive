# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    class Result
      ErrorTypes = T.type_alias do
        T.any(
          Errors::DiscountRequestCreationFailed,
          Errors::DuplicatePhoto,
          Errors::EnterpriseManagedUser,
          Errors::MissingFarFromCampusProof,
          Errors::None,
          Errors::UnverifiedSchoolEmail,
          Errors::UserNotEligible,
        )
      end

      sig { params(subject: EducationDeveloperPackApplicationMetadata, response: T.untyped).void }
      def initialize(subject:, response:)
        @subject = subject
        @response = response
      end

      sig { returns(T.nilable(T::Boolean)) }
      def success?
        @subject.valid? && successful_response?
      end

      sig { returns(ErrorTypes) }
      def error
        if @subject.errors.any?
          Errors::UserNotEligible.new
        elsif unverified_school_email?
          Errors::UnverifiedSchoolEmail.new
        elsif enterprise_managed_user?
          Errors::EnterpriseManagedUser.new
        elsif !successful_response?
          message = response_data&.discount_request_status_result&.message || "There was a problem"

          GitHub.logger.error(
            "edu-devpack application failed",
            "response" => @response.inspect,
            "response.error.meta" => @response.error&.meta.inspect,
            "gh.user.login" => User.find_by(id: @subject.user_id)&.display_login,
          ) if message == "There was a problem"

          if duplicate_photo?
            Errors::DuplicatePhoto.new(message:)
          elsif missing_far_from_campus_proof?
            Errors::MissingFarFromCampusProof.new(message:)
          else
            Errors::DiscountRequestCreationFailed.new(message:)
          end
        else
          Errors::None.new
        end
      end

      sig { returns(T::Boolean) }
      def unverified_school_email?
        @response == :unverified_school_email
      end

      sig { returns(T::Boolean) }
      def enterprise_managed_user?
        @response == :enterprise_managed_user
      end

      sig { returns(T.nilable(Integer)) }
      def discount_request_id
        response_data&.discount_request_status_result&.discount_request_id
      end

      sig { returns(T::Boolean) }
      def duplicate_photo?
        validly_shaped_response? &&
          response_data&.discount_request_status_result&.status == :DISCOUNT_REQUEST_STATUS_DUPLICATE_PHOTO_PROOF
      end

      sig { returns(T::Boolean) }
      def missing_far_from_campus_proof?
        validly_shaped_response? &&
          response_data&.discount_request_status_result&.status == :DISCOUNT_REQUEST_STATUS_MISSING_FAR_FROM_CAMPUS_PROOF
      end

      private

      sig { returns(T::Boolean) }
      def successful_response?
        validly_shaped_response? && !(duplicate_photo? || missing_far_from_campus_proof? || invalid?) &&
          !discount_request_id.nil? && discount_request_id != 0
      end

      sig { returns(T::Boolean) }
      def invalid?
        validly_shaped_response? &&
          response_data&.discount_request_status_result&.status == :DISCOUNT_REQUEST_STATUS_UNKNOWN_INVALID
      end

      sig { returns(T::Boolean) }
      def validly_shaped_response?
        response_data.is_a?(EducationWeb::V1::CreateDiscountRequestResponse)
      end

      sig { returns(T.nilable(EducationWeb::V1::CreateDiscountRequestResponse)) }
      def response_data
        @response.try(:data)
      end
    end
  end
end
