# typed: true
# frozen_string_literal: true

module TurboHelper
  include Kernel

  def turbo_cache_control_tag
    return unless respond_to?(:turbo_cache_control_value)

    cache_control_value = T.unsafe(self).turbo_cache_control_value

    if cache_control_value != "preview"
      T.unsafe(self).tag.meta(name: "turbo-cache-control", content: cache_control_value, "data-turbo-transient": "")
    end
  end

  def turbo_frame_attr(id:, hash: false, flagged: false)
    if flagged
      return hash ? {} : nil
    end

    hash ? { "data-turbo-frame": id } : "data-turbo-frame=\"#{id}\""
  end

  def repo_turbo_frame_attr(hash: false, flagged: false)
    turbo_frame_attr(id: "repo-content-turbo-frame", hash: hash, flagged: flagged)
  end
end
