# typed: true
# frozen_string_literal: true

module CommandPalette
  module Commands
    class CloneCopySsh < CopyableCommand
      scope_type "Repository", "Issue", "PullRequest", "Discussion"

      display_as "Copy Clone SSH URL", icon: "copy"

      def enabled?
        repository.readable_by?(current_user) && repository.ssh_enabled?
      end

      def copyable_text
        repository.ssh_url
      end

      def copyable_message
        "Clone URL copied!"
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
