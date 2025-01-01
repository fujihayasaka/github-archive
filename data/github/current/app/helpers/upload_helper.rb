# typed: false
# frozen_string_literal: true

module UploadHelper
  include TagAttributeHelper

  class InvalidPolicyError < StandardError; end

  # Helper to get an array of all of the extensions that users are allowed to upload for
  # a given model that an upload is for.
  #
  # model_name - The String or Symbol model that the upload is for (Eg. `:avatars`).
  #
  # Returns an array of file extensions (eg: `[".jpg", ".gif"]`)
  def upload_policy_allowed_extensions(model_names)
    extensions = Array(model_names).flat_map do |model_name|
      policy = ::Storage.policy_creator.for(model_name)

      unless policy
        raise InvalidPolicyError, "Storage policy for #{model_name} not found"
      end

      if policy.model == UserAsset
        policy.model.user_allowed_content_extensions(actor: current_user)
      else
        policy.model.user_allowed_content_extensions
      end
    end

    extensions.uniq
  end

  # Helper to make an `accept` attribute for input[type="file"], which prevents users from
  # selecting file types that will be rejected by the upload policy.
  #
  # model_name - The String or Symbol model that the upload is for (Eg. `:avatars`).
  #
  # Returns an HTML safe String for the `accept` attribute
  def upload_policy_accept_extensions_attribute(model_names)
    attrs = {
      "accept" => upload_policy_allowed_extensions(model_names).join(","),
    }

    tag_attributes(attrs)
  end

  # Helper to make a human-readable list of allowed extensions, used to populate error messages
  # on the form if an unacceptable file is uploaded.
  #
  # model_name - The String or Symbol model that the upload is for (Eg. `:avatars`).
  #
  # Returns a String of uppercase file extensions (minus the "." stop character)
  # and separated by a comma and a space (eg: "JPG, PNG")
  def upload_policy_friendly_extensions(model_names)
    extensions = upload_policy_allowed_extensions(model_names)

    # remove stop characters, convert to upper case
    extensions = extensions.map { |ext| ext.tr(".", "").upcase }

    "#{extensions.to_sentence(last_word_connector: ' or ')}."
  end

  # Renders a <file-attachment> custom element if file uploads are enabled,
  # otherwise just renders the block content.
  #
  # Examples
  #
  #   <%= file_attachment_tag(model: :assets, class: "is-default") do |enabled| %>
  #     <div class="<%= "upload-enabled" if enabled %>"></div>
  #   <% end %>
  #
  # Returns an HTML string.
  def file_attachment_tag(**options)
    model = options.delete(:model)

    path = if defined?(this_organization) && this_organization.present?
      upload_policy_path(model, org: this_organization.display_login)
    else
      upload_policy_path(model, subject_type: options[:subject_type], subject: options[:subject])
    end

    # When uploading assets, we want to know the container type and its id
    if model == :assets || model == "assets"
      case controller
      when Settings::SavedRepliesController
        options = options.merge(
          "data-upload-container-type" => "user",
          "data-upload-container-id" => current_user.id
        ) if defined?(current_user) && current_user.present?
      when Gists::GistsController, Gists::CommentsController
        options = merge_options_for_gists(options)
      when Repos::AdvisoriesController
        if current_user&.feature_flag_enabled?(:secured_advisory_uploads, default: true)
          options = options.merge(
            "data-upload-container-type" => "repository_advisory"
          )
          options = options.merge(
              "data-upload-container-id" => controller.send(:advisory).id
          ) if safe_to_fetch_advisory_id?
        end
      end
    end

    options = options.merge(
      "data-upload-policy-url" => path,
    )

    enabled = options.key?(:enabled) ? options.delete(:enabled) : true
    enabled = enabled && attachments_enabled?

    if enabled
      content_tag("file-attachment", options) do
        concat(csrf_hidden_input_for(path, class: "js-data-upload-policy-url-csrf"))
        yield enabled
      end
    else
      capture do
        yield enabled
      end
    end
  end

  private def merge_options_for_gists(options)
    # Handles uploads originating from app/views/editors/_file.html.erb. This is specifically for files that support
    # uploads, such as Markdown (.md) files.
    if options[:data].is_a?(Hash)
      options[:data]["upload-container-type"] = Gist.name.downcase
      if controller.respond_to?(:this_gist, true) && controller.send(:this_gist)
        options[:data]["upload-container-id"] = controller.send(:this_gist).id
      end

      return options
    end

    # For gist's comments
    subject_param = options[:"data-subject-param"]
    return options unless subject_param.is_a?(Gist)

    options.merge(
      "data-upload-container-type" => Gist.name.downcase,
      "data-upload-container-id" => subject_param.id
    )
  end

  private def safe_to_fetch_advisory_id?
    return false if controller.nil? || !controller.is_a?(Repos::AdvisoriesController)
    # It is only safe to fetch the ID of a repository advisory if the following conditions are met:
    # 1.  The controller has an `id` query parameter, indicating that the advisory has been created and we're visiting
    #     an advisory page.
    # 2. The controller has a `current_repository`, indicating that we're within the context of a valid repository.
    # 3. If the controller has an `advisory` model, indicating that we're within the context of a valid advisory.
    !controller.params[:id].nil? &&
      controller.respond_to?(:current_repository, true) && !controller.send(:current_repository).nil? &&
      controller.respond_to?(:advisory, true) && !controller.send(:advisory).nil?
  end

  def paid_upload_policy?(owner)
    return true if GitHub.enterprise?
    return paid_org_upload_policy?(owner) if owner.is_a?(Organization)

    paid_user_upload_policy?(owner) if owner.present?
  end

  def paid_org_upload_policy?(org)
    # In order to upload an oversized video to an org-owned repo or team post,
    # the org must be on a paid plan and the uploader must be associated with
    # that org or also be on a paid plan.
    return false unless logged_in?
    return false unless org.paid_non_trial_plan?

    org.direct_member?(current_user) ||
      org.user_is_outside_collaborator?(current_user) ||
      current_user.paid_plan?
  end

  def paid_user_upload_policy?(owner)
    return false unless logged_in?

    # In order to upload an oversized video to a user-owned repo or gist,
    # both the owner and the uploader must be on a paid plan.
    owner.paid_plan? && current_user.paid_plan?
  end
end
