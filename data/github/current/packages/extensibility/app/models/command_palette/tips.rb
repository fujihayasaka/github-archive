# typed: true
# frozen_string_literal: true

module CommandPalette
  class Tips

    ITEMS = [
      Tip.new(
        title: "to search pull requests",
        prefix: "#",
        scope_types: [:global, :owner, :repository]
      ),
      Tip.new(
        title: "to search issues",
        prefix: "#",
        scope_types: [:global, :owner, :repository]
      ),
      Tip.new(
        title: "to search discussions",
        prefix: "#",
        scope_types: [:owner, :repository]
      ),
      Tip.new(
        title: "to search projects",
        prefix: "!",
        scope_types: [:owner, :repository]
      ),
      Tip.new(
        title: "to search teams",
        prefix: "@",
        scope_types: [:owner]
      ),
      Tip.new(
        title: "to search people and organizations",
        prefix: "@",
        scope_types: [:global]
      ),
      Tip.new(
        title: "to activate command mode",
        prefix: ">",
        scope_types: [:global, :owner, :repository]
      ),
      Tip.new(
        title: "Go to your accessibility settings to change your keyboard shortcuts",
        scope_types: [:global, :owner, :repository]
      ),

      # mode: search
      Tip.new(
        title: "Type author:@me to search your content",
        mode: "#",
        scope_types: [:global, :owner, :repository]
      ),
      Tip.new(
        title: "Type is:pr to filter to pull requests",
        mode: "#",
        scope_types: [:global, :owner, :repository]
      ),
      Tip.new(
        title: "Type is:issue to filter to issues",
        mode: "#",
        scope_types: [:global, :owner, :repository]
      ),
      Tip.new(
        title: "Type is:project to filter to projects",
        mode: "#",
        scope_types: [:owner, :repository]
      ),
      Tip.new(
        title: "Type is:open to filter to open content",
        mode: "#",
        scope_types: [:global, :owner, :repository]
      ),
    ]

    def self.all
      ITEMS
    end
  end
end
