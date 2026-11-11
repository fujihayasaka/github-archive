# typed: true
# frozen_string_literal: true

module Api::Serializer::PreReceiveDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }

  def pre_receive_environment_hash(environment, options = {})
    return nil unless environment
    {
      id: environment.id,
      name: environment.name,
      image_url: environment.image_url,
      url: url("/admin/pre-receive-environments/#{environment.id}", options),
      html_url: html_url("/admin/pre_receive_environments/#{environment.id}"),
      default_environment: environment.default_environment?,
      created_at: environment.created_at,
      hooks_count: environment.hooks_count,
      download: pre_receive_environment_download_hash(environment, options),
    }
  end

  def pre_receive_environment_download_hash(environment, options = {})
    return nil unless environment
    {
      url: url("/admin/pre-receive-environments/#{environment.id}/downloads/latest", options),
      state: environment.download_state,
      message: environment.download_message,
      downloaded_at: time(environment.downloaded_at),
    }
  end

  # Common elements for pre-receive hook and target hashes
  def pre_receive_hook_common_hash(target, options = {})
    return nil unless target
    {
      id: target.hook.id,
      name: target.hook.name,
      enforcement: target.enforcement_display,
    }
  end

  def pre_receive_hook_hash(target, options = {})
    return nil unless target
    pre_receive_hook_common_hash(target, options).merge(
      script: target.hook.script,
      script_repository: {
        id: target.hook.repository.id,
        full_name: target.hook.repository.full_name,
        url: url("/repos/#{target.hook.repository.name_with_owner_for_api(use: options[:serialize_login])}", options),
        html_url: target.hook.repository.permalink,
      },
      environment: pre_receive_environment_hash(target.hook.environment, options),
      allow_downstream_configuration: target.allow_downstream_configuration,
    )
  end

  def pre_receive_repo_target_hash(target, options = {})
    return nil unless target
    pre_receive_hook_common_hash(target, options).merge(
      configuration_url: target_hookable_url(target, options),
    )
  end

  def pre_receive_org_target_hash(target, options = {})
    return nil unless target
    pre_receive_repo_target_hash(target, options).merge(
      allow_downstream_configuration: target.allow_downstream_configuration,
    )
  end

  # Helper method to create a configuration_url for a pre-receive hook target base on the type of hookable.
  def target_hookable_url(target, options = {})
    hookable = target.hookable
    hookable_url =
      case hookable
      when Business
        "/admin"
      when Repository
        "/repos/#{hookable.name_with_owner_for_api(use: options[:serialize_login])}"
      when Organization
        "/orgs/#{hookable.name}"
      else
        nil
      end
    hookable_url ? url("#{hookable_url}/pre-receive-hooks/#{target.hook.id}") : nil
  end
end
