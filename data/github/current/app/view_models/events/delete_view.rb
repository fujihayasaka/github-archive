# typed: false
# frozen_string_literal: true

module Events
  class DeleteView < View
    def title_text
      parts = [pusher_text, actor_bot_identifier_text, "deleted", ref_type, ref, "at", repo_text]
      parts.compact.join(" ")
    end

    def icon
      if ref_type == "tag"
        "tag"
      elsif ref_type == "branch"
        "git-branch"
      else
        "circle-slash"
      end
    end
  end
end
