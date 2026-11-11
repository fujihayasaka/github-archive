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
        # BEGIN: Log image dimensions before Twirp call for observability
        # Extract dimensions from base64 data URLs to track upload patterns without PII

        if FeatureFlag.vexi.enabled?("log_education_developer_pack_image_metrics", user, default: false)
          log_image_upload_metrics(photo_proof_attributes)
        end
        # END: Image upload logging

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
        @photo_proof_attributes ||= T.let(
          {
            photo_proof: base64_image_for(form_values[:photo_proof]),
            photo_proof_binary_data: binary_data_for(form_values[:photo_proof]),
            far_from_campus_proof: base64_image_for(form_values[:far_from_campus_proof]),
            far_from_campus_proof_binary_data: binary_data_for(form_values[:far_from_campus_proof]),
          }.compact,
          T.nilable(T::Hash[Symbol, T.untyped])
        )
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

      # BEGIN: JPEG dimension parser for image upload logging
      # Extracts width/height from base64 data URL JPEGs using pure Ruby JPEG header parsing
      # Returns [width, height] or [nil, nil] if unable to parse
      #
      # Example usage:
      #   extract_jpeg_dimensions("data:image/jpeg;base64,/9j/4AAQ...") => [1920, 1080]
      #   extract_jpeg_dimensions("invalid_data") => [nil, nil]
      #   extract_jpeg_dimensions("data:image/png;base64,...") => [nil, nil] (not JPEG)
      sig { params(data_url: T.nilable(String)).returns([T.nilable(Integer), T.nilable(Integer)]) }
      def extract_jpeg_dimensions(data_url)
        return [nil, nil] unless data_url.present?

        # Strip data URL prefix if present (e.g., "data:image/jpeg;base64,")
        base64_data = data_url.include?(",") ? data_url.split(",", 2).last : data_url
        return [nil, nil] unless base64_data.present?

        begin
          binary_data = Base64.strict_decode64(base64_data)
        rescue ArgumentError => e
          GitHub.logger.error("Failed to decode base64 image data", e)
          return [nil, nil]
        end

        parse_jpeg_dimensions(binary_data)
      end

      # Minimal JPEG parser that scans for SOF (Start of Frame) markers to read width/height
      # JPEG format: FF D8 (SOI) ... FF C0-C3 (SOF0-SOF3) [length] [precision] [height] [width] ...
      # Returns [width, height] or [nil, nil] if not a valid JPEG or SOF not found
      sig { params(binary_data: String).returns([T.nilable(Integer), T.nilable(Integer)]) }
      def parse_jpeg_dimensions(binary_data)
        return [nil, nil] if binary_data.length < 10

        return [nil, nil] unless binary_data[0, 2] == "\xFF\xD8"

        sof_markers = ["\xFF\xC0", "\xFF\xC1", "\xFF\xC2", "\xFF\xC3"]
        offset = 2 # Skip SOI marker

        while offset < binary_data.length - 8
          marker_pos = binary_data.index("\xFF", offset)
          break unless marker_pos && marker_pos < binary_data.length - 1

          marker = binary_data[marker_pos, 2]

          if sof_markers.include?(marker)
            dim_offset = marker_pos + 5
            return [nil, nil] if dim_offset + 4 > binary_data.length

            height_bytes = binary_data[dim_offset, 2]
            width_bytes = binary_data[dim_offset + 2, 2]
            return [nil, nil] unless height_bytes && width_bytes

            height = height_bytes.unpack1("n")
            width = width_bytes.unpack1("n")

            return [width, height]
          else

            offset = marker_pos + 2
            next if offset >= binary_data.length - 2

            length_bytes = binary_data[offset, 2]
            next unless length_bytes
            segment_length = length_bytes.unpack1("n")
            offset += segment_length
          end
        end

        [nil, nil] # No SOF marker found
      end

      # Logs image dimensions and sizes for uploaded photos without exposing PII
      sig { params(photo_attrs: T::Hash[Symbol, T.untyped]).void }
      def log_image_upload_metrics(photo_attrs)
        return unless photo_attrs.present?

        request_id = GitHub.context[:request_id]

        log_parts = {
          "gh.request.id" => request_id,
          "gh.education_web.developer_pack_photo_upload.stage" => "twirp_request",
          "gh.education_web.developer_pack_photo_upload.keys_present" => "#{photo_attrs.keys.join(',')}"
        }

        # Log dimensions and payload size for photo_proof
        if photo_attrs[:photo_proof].present?
          width, height = extract_jpeg_dimensions(photo_attrs[:photo_proof])
          payload_size = photo_attrs[:photo_proof].length
          dimension_str = width && height ? "#{width}x#{height}" : "unknown"
          log_parts["photo_proof"] = "#{dimension_str}(bytes=#{payload_size})"

          # Report to DataDog using extracted dimensions
          if width
            GitHub.dogstats.distribution("education_web.developer_pack_photo_upload.photo_proof.width", width, tags: ["service:education-web"])
          end
          if height
            GitHub.dogstats.distribution("education_web.developer_pack_photo_upload.photo_proof.height", height, tags: ["service:education-web"])
          end
        end

        # Log dimensions and payload size for far_from_campus_proof
        if photo_attrs[:far_from_campus_proof].present?
          width, height = extract_jpeg_dimensions(photo_attrs[:far_from_campus_proof])
          payload_size = photo_attrs[:far_from_campus_proof].length
          dimension_str = width && height ? "#{width}x#{height}" : "unknown"
          log_parts["far_from_campus_proof"] = "#{dimension_str}(bytes=#{payload_size})"

          if width
            GitHub.dogstats.distribution("education_web.developer_pack_photo_upload.far_from_campus_proof.width", width, tags: ["service:education-web"])
          end
          if height
            GitHub.dogstats.distribution("education_web.developer_pack_photo_upload.far_from_campus_proof.height", height, tags: ["service:education-web"])
          end
        end

        # Emit single Splunk-friendly log line
        GitHub.logger.info("developer_pack_photo_upload", log_parts)
      end
    end
  end
end
