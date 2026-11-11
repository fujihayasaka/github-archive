# typed: false
# frozen_string_literal: true

module Configurable
  module RepositoryExportedToUrl
    PREFIX = "repository.exported_to_url"

    def repository_exported_to_url_enabled?
      config.enabled?(exported_to_url_config_key)
    end

    # Public: Gets the repository exported_to_url value
    #
    # Returns exported_to_url or false
    def get_repository_exported_to_url
      config.get(exported_to_url_config_key)
    end

    # Public: Set repository exported_to_url
    #
    # Acceptable values:
    #   target_url     - valid URL with https or http
    #
    # actor - Repository that owns this config value
    #
    # Returns nothing

    def set_repository_exported_to_url(target_url, actor: owner)
      if target_url.nil?
        delete_repository_exported_to_url
      else
        config.enable(exported_to_url_config_key, actor)
        config.set!(exported_to_url_config_key, target_url, actor)
      end
    end

    # Public: Delete repository exported_to_url setting
    #
    # Removes the configuration setting entirely
    #
    # actor - Repository clearing the value
    #
    # Returns nothing

    def delete_repository_exported_to_url(actor: owner)
      config.delete(exported_to_url_config_key, actor)
    end

    private

    # Private: Create key to be used to store settings in config table
    #
    # key_suffix - in this case repo name with owner
    #
    # Returns string

    def exported_to_url_config_key
      @_exported_to_url_config_key ||= [PREFIX, name_with_owner].join("-")
    end
  end
end
