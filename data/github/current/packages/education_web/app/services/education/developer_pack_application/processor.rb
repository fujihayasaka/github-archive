# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    class Processor
      sig { params(user: User, form_values: T::Hash[Symbol, String], ip_address: String).returns(Result) }
      def self.call(user:, form_values:, ip_address:)
        new(user:, form_values:, ip_address:).call
      end

      sig { params(user: User, form_values: T::Hash[Symbol, String], ip_address: String).void }
      def initialize(user:, form_values:, ip_address:)
        @user = user
        @form_values = form_values
        @ip_address = ip_address
      end

      sig { returns(Result) }
      def call
        subject = EducationDeveloperPackApplicationMetadata.new(
          user:,
          application_type:,
          applied_at:,
        )

        # Return early with error if user is an enterprise managed user
        if user.is_enterprise_managed?
          return Result.new(
            subject:,
            response: :enterprise_managed_user
          )
        end

        # Return early with error if school email is not verified
        if !school_email_verified?
          return Result.new(
            subject:,
            response: :unverified_school_email
          )
        end

        response = discount_requests_client.create_discount_request(
          discount_request:,
          ip_address:,
        )

        result = Result.new(subject:, response:)

        if result.success?
          subject.update(external_discount_request_id: result.discount_request_id)
        elsif result.discount_request_id == 0
          Rails.logger.warn(
            "Discount request created with ID 0 for user #{user.id}. " \
            "This may indicate an issue with the request.",
          )
        end

        result
      end

      private

      # Check if the provided school email is provided and one of the user's verified emails.
      sig { returns(T::Boolean) }
      def school_email_verified?
        return false unless form_values[:school_email].present?

        # Access user's verified emails and check if the school email is among them.
        user.emails.verified.exists?(email: form_values[:school_email])
      end

      sig { returns(User) }
      attr_reader :user

      sig { returns(T::Hash[Symbol, String]) }
      attr_reader :form_values

      sig { returns(String) }
      attr_reader :ip_address

      sig { returns(Symbol) }
      def application_type
        T.must(form_values[:application_type]).to_sym
      end

      sig { returns(DateTime) }
      def applied_at
        DateTime.now
      end

      sig { returns(Education::Twirp::DiscountRequestsClient) }
      def discount_requests_client
        Education::Twirp::DiscountRequestsClient.new(user:)
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def discount_request
        {
          application_type: form_values[:application_type],
          far_from_campus_reason: form_values[:far_from_campus_reason],
          github_user_id: user.id,
          latitude: form_values[:latitude]&.to_f,
          longitude: form_values[:longitude]&.to_f,
          new_school_location_address: form_values[:location_address],
          new_school_location_city: form_values[:location_city],
          new_school_location_country: form_values[:location_country],
          new_school_location_state_or_province: form_values[:location_state_or_province],
          new_school_name: form_values[:school_name],
          new_school_number_of_students: form_values[:number_of_students],
          new_school_student_email_sample_address: form_values[:student_email_sample_address],
          new_school_teacher_email_sample_address: form_values[:teacher_email_sample_address],
          new_school_type: form_values[:school_type],
          new_school_website: form_values[:school_website],
          octo_cookie_content: form_values[:octo_cookie_content],
          other_reason_text: form_values[:other_reason_text],
          proof_type: form_values[:proof_type],
          school_email: form_values[:school_email],
          school_name: form_values[:school_name],
          selected_school_id: form_values[:selected_school_id].to_i,
          utm_content: form_values[:utm_content],
          utm_source: form_values[:utm_source],
        }.merge(photo_proof_attributes).compact
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def photo_proof_attributes
        {
          photo_proof: base64_image_for(form_values[:photo_proof]),
          photo_proof_binary_data: binary_data_for(form_values[:photo_proof]),
          far_from_campus_proof: base64_image_for(form_values[:far_from_campus_proof]),
          far_from_campus_proof_binary_data: binary_data_for(form_values[:far_from_campus_proof]),
        }.compact
      end

      sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
      def base64_image_for(value)
        return unless value.present?
        parsed_data = parsed_data_for(value)
        return unless parsed_data.present?

        parsed_data["image"]
      end

      sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
      def binary_data_for(value)
        return unless value.present?
        parsed_data = parsed_data_for(value)
        return unless parsed_data.present?

        { metadata: parsed_data["metadata"].transform_keys(&:underscore) }.to_json
      end


      sig { params(value: String).returns(T.nilable(T::Hash[String, T.untyped])) }
      def parsed_data_for(value)
        JSON.parse(value)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
