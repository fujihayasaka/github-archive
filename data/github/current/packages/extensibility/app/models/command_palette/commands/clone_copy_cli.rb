# typed: true
# frozen_string_literal: true

module CommandPalette
  module Commands
    class CloneCopyCli < CopyableCommand
      scope_type "Repository", "Issue", "PullRequest", "Discussion"

      display_as "Copy GitHub CLI Clone Command", icon: "copy"

      def enabled?
        repository.readable_by?(current_user)
      end

      def copyable_text
        host = GitHub.enterprise? ? "#{GitHub.host_name}/" : ""
        "gh repo clone #{host}#{repository.name_with_owner}"
      end

      def copyable_message
        "Clone command copied!"
      end

      def repository
        if scoped_object.class.name == "Repository"
          scoped_object
        else
          scoped_object.repository
        end
      end
    end
  end
end
