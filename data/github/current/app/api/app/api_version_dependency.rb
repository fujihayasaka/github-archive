# typed: false
# frozen_string_literal: true

module Api::App::ApiVersionDependency
  IGNORED_PATHS = %w(
    /applications
    /chunks
    /code
    /copilot_internal
    /embeddings
    /graphql
    /internal
    /lsp
    /symbols
  ).freeze

  # Assigns `@selected_api_version` based on the incoming headers or the default version.
  def set_selected_api_version_for_request
    if (preset_version = env["github.api.test_selected_version"])
      # This is set by tests, short-circuit the selection logic below
      @selected_api_version = preset_version
      return
    elsif request.path_info.starts_with?(*IGNORED_PATHS)
      requested_version_raw = nil
      selected_version = nil
      version_selection_reason = Api::SelectedVersion::REASON_SKIPPED
    else
      # Favor permissiveness when comparing version strings provided by the client
      # Convert to string so that we can downcase and compare
      requested_version_raw = request.env[Api::SelectedVersion::ENV_REQUESTED_API_VERSION]
      requested_version = requested_version_raw.to_s.downcase.gsub(/\s+/, "")
      # When a X-GitHub-API-Version is not provided:
      #   If we've published any versions, the earliest supported version should be selected. (This is the default)
      #   If we haven't published any versions, set the version to nil and mark it as unavailable
      # When a X-GitHub-API-Version header is provided:
      #   If it's for an invalid/unsupported version, an error should be returned
      #   If it's for a valid calendar version or next, the version should be selected
      if requested_version.blank?
        # If no version was requested, pick the default
        selected_version = Api::Versioning.default_version
        if selected_version
          version_selection_reason = Api::SelectedVersion::REASON_DEFAULT
        else
          version_selection_reason = Api::SelectedVersion::REASON_UNAVAILABLE
        end
      elsif Api::Versioning.usable_version?(requested_version)
        # only allow 'next' to be used by staff
        if requested_version.to_s == Api::SelectedVersion::NEXT_VERSION && !api_version_next_enabled?
          selected_version = nil
          version_selection_reason = Api::SelectedVersion::REASON_INVALID
        else
          selected_version = requested_version
          version_selection_reason = Api::SelectedVersion::REASON_REQUEST_HEADER
        end
      else
        selected_version = nil
        version_selection_reason = Api::SelectedVersion::REASON_INVALID
      end
    end

    @selected_api_version = Api::SelectedVersion.new(requested_version_raw, selected_version, version_selection_reason)

    # Make sure the assigned version is valid:
    if !@selected_api_version.skipped? && @selected_api_version.invalid?
      latest_version, *other_versions = GitHub.api_versions
      message = if latest_version.nil?
        "There are no published API versions. Please omit #{Api::SelectedVersion::HTTP_HEADER_API_REQUESTED_VERSION.inspect}"
      else
        versions_string = [
          "#{latest_version.inspect} (most recent)",
          *other_versions.map(&:inspect)
        ].to_sentence

        <<~ERR.chomp
          The version you specified in the "#{Api::SelectedVersion::HTTP_HEADER_API_REQUESTED_VERSION}" request header, "#{@selected_api_version.requested_version}", is not a supported version. The following versions are currently supported: #{versions_string}.
        ERR
      end
      deliver_error! 400, errors: message
    end

    nil
  end

  def set_selected_api_version_response_headers
    if @selected_api_version &&
      !@selected_api_version.skipped? &&
      !@selected_api_version.invalid?

      headers[Api::SelectedVersion::HTTP_HEADER_API_SELECTED_VERSION] = @selected_api_version.version.to_s
    end
  end

  def api_version_next_enabled?
    GitHub.flipper[:api_versioning_allowed_next].enabled?(current_user)
  end

  private

  def api_version_client
    if !defined?(@api_version_client)
      @api_version_client = current_integration || current_app || current_user
    end
    @api_version_client
  end
end
