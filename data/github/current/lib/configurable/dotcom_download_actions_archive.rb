# typed: false
# frozen_string_literal: true

# Whether fetching Actions from dotcom is enabled.
module Configurable
  module DotcomDownloadActionsArchive
    KEY = "dotcom_download_actions_archive".freeze

    def enable_dotcom_download_actions_archive(actor)
      config.enable(KEY, actor)
    end

    def disable_dotcom_download_actions_archive(actor)
      config.disable(KEY, actor)
    end

    def dotcom_download_actions_archive_enabled?
      config.enabled?(KEY)
    end
  end
end
