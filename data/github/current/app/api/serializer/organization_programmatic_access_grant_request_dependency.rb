# typed: true
# frozen_string_literal: true

module Api::Serializer::OrganizationProgrammaticAccessGrantRequestDependency
  extend T::Helpers
  include GranularPermissionsHelper

  requires_ancestor { T.class_of(Api::Serializer) }

  def get_expiration_fields_for(access)
    token_expiration = ProgrammaticAccessToken.expiration_for(access).value
    expired = false

    if token_expiration == :expired
      expired = true
      token_expiration = nil
    end

    [token_expiration&.iso8601, expired]
  end

  def org_pat_grant_request_hash(request, options = {})
    options = Api::SerializerOptions.from(options)
    access = request.user_programmatic_access

    if options[:expires_at].nil? || options[:expired].nil?
      token_expiration, expired = get_expiration_fields_for(access)
    else
      token_expiration, expired = options[:expires_at], options[:expired]
    end

    {}.tap do |h|
      h[:id] = request.id
      h[:reason] = request.reason unless options[:hook] # Don't include reason in webhook payload to keep it small.
      h[:owner] = simple_user_hash(access.owner, content_options(options))
      h[:repository_selection] = request.repository_selection

      # If we're serializing a webhook event
      if options[:hook]
        h[:repository_count] = options[:repositories]&.size
        h[:repositories] = options[:repositories]
        h[:permissions_added] = permissions_by_subject_type_hash(options[:permissions_added])
        h[:permissions_upgraded] = permissions_by_subject_type_hash(options[:permissions_upgraded])
        h[:permissions_result] = permissions_by_subject_type_hash(options[:permissions_result])
      else
        h[:repositories_url] = url("/organizations/#{request.organization_id}/personal-access-token-requests/#{request.id}/repositories")
        h[:permissions] = permissions_by_subject_type_hash(request.permissions)
      end

      h[:created_at] = request.created_at.iso8601
      h[:token_id] = access.id
      h[:token_name] = access.name
      h[:token_expired] = expired
      h[:token_expires_at] = token_expiration
      h[:token_last_used_at] = access.accessed_at&.iso8601
    end
  end
end
