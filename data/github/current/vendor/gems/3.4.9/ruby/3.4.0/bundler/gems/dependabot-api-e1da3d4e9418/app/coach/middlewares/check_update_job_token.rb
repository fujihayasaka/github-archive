# frozen_string_literal: true

require "digest"
require "rbnacl"
require "renderer"

module Middlewares
  class CheckUpdateJobToken < Coach::Middleware
    uses CheckParams, id: { type: [String, Integer] }

    provides :token, :update_job

    def call
      return no_token_error if token.nil?

      unless token_valid
        log_validation_failure
        return invalid_token_error
      end

      provide(token: token)
      provide(update_job: update_job)

      # Append UpdateJob information to the error context
      if update_job
        Dependabot::Exceptions.push(
          "gh.dependabot_api.update_config.package_manager": update_job.update_config&.package_manager,
          "gh.dependabot_api.update_job.trigger_type": update_job.trigger_type,
          **update_job.telemetry_attributes,
        )
      end

      next_middleware.call
    end

    private

    def token
      base_64_token = request.headers["Authorization"]
      return if base_64_token.nil?

      original_token = base_64_token

      # New job/cred token has prefix of dependabot-job_/dependabot-cred_ respectively with a
      # 32 bit checksum in the last 6 digits of each token.
      # Format of new job token: "dependabot-job_L4aB8YbwZrxDsTNTzn0RTFDFVkVzxN/AhQJcvumMUu0=0nE82Q".
      # Format of new cred token: "dependabot-cred_DFaB8YbwZrxDsTNTzn0RTFDFVkVzxN/AhQJcvumMUu0=0nE83W".
      # Format of old job/cred token: "IpDNP68e/u1eKGNgoSRYJr8cBsJ3aFpDTntHZASbQzU=".
      prefixes = [UpdateJob::DEPENDABOT_JOB_TOKEN_PREFIX, UpdateJob::DEPENDABOT_CRED_TOKEN_PREFIX]
      # The guard is here to ensure that if we still have older jobs queued up, they will
      # attempt to fetch job details using the old token.
      if prefixes.any? { |prefix| base_64_token.start_with?(prefix) }
        # Using new token with prefix and checksum
        base_64_token = prefixes.reduce(base_64_token) { |str, prefix| str.delete_prefix(prefix) }
        # Removing checksum from the base_64_token token
        base_64_token = base_64_token[0..-7]
      end

      # Cache decoding the token, since this method is used several times
      @decoded_token ||= Base64.strict_decode64(base_64_token)
    rescue ArgumentError => e
      @decode_error = e
      log_token_decode_failure(original_token, base_64_token, e)
      # If the token can't be Base64 decoded, leave it as is.
      base_64_token
    end

    def log_token_decode_failure(original_token, processed_token, error)
      Dependabot::Logger.error(
        msg: "Token decode failed",
        "code.namespace": "Middlewares::CheckUpdateJobToken",
        "job.id": job_id,
        original_token_length: original_token&.length,
        processed_token_length: processed_token&.length,
        error: error.message
      )
    end

    def job_id
      params[:id].to_i
    end

    def token_valid
      update_job.present?
    end

    def update_job
      return if token.nil?

      @update_job ||=
        begin
          @hashed_token = Base64.strict_encode64(RbNaCl::Hash.sha256(token))

          if config[:type] == :credentials
            UpdateJob.find_by(
              id: job_id,
              hashed_credentials_token: @hashed_token
            )
          else
            UpdateJob.find_by(id: job_id, hashed_token: @hashed_token)
          end
        end
    end

    def log_validation_failure
      Dependabot::Logger.warn(
        msg: "Token validation failed",
        "code.namespace": "Middlewares::CheckUpdateJobToken",
        "job.id": job_id,
        token_type: config[:type],
        received_token_hash: @hashed_token&.then { |v| Digest::SHA256.hexdigest(v)[0, 12] },
        decode_error: @decode_error&.message
      )
    end

    def no_token_error
      Renderer.render_error(
        status: 401,
        title: "Unauthorized",
        detail: "No token provided in the Authorization header",
      )
    end

    def invalid_token_error
      Renderer.render_error(
        status: 403,
        title: "Forbidden",
        detail: "Token invalid",
      )
    end
  end
end
