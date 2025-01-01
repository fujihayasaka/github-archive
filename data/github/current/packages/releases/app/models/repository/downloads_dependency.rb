# typed: true
# frozen_string_literal: true

module Repository::DownloadsDependency
  extend T::Helpers

  requires_ancestor { Repository }

  ANONYMOUS_RELEASE_DOWNLOAD_DISABLED_KEY = "release_anonymous_download.disabled"

  def toggle_anonymous_release_download(enable, actor)
    return if GitHub.enterprise?

    if enable
      config.delete(ANONYMOUS_RELEASE_DOWNLOAD_DISABLED_KEY, actor)
    else
      config.enable(ANONYMOUS_RELEASE_DOWNLOAD_DISABLED_KEY, actor)
    end
  end

  def anonymous_release_download_disabled?
    !GitHub.enterprise? && config.enabled?(ANONYMOUS_RELEASE_DOWNLOAD_DISABLED_KEY)
  end
end
