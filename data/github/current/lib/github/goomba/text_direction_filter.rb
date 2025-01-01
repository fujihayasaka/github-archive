# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Apply the dir="auto" HTML attribute to each text block so browsers
  # right-align those written in a right-to-left language (e.g. Arabic, Hebrew)
  class TextDirectionFilter < NodeFilter
    # Apply the attribute to p, h* and div elements so each Markdown paragraph
    # aligns individaully, and to ul/ol so the list aligns as a whole.
    # Task lists are excluded due to a Blink (Chrome/Safari/Edge) bug; see:
    # https://github.com/github/special-projects/issues/568#issuecomment-951052706
    SELECTOR = Goomba::Selector.new(match: "p,h1,h2,h3,h4,h5,h6,div,ul:not(.contains-task-list),ol:not(.contains-task-list)")

    # Target all user-generated content that belongs to a repository or a gist
    # (excluding things such as e-mails).
    def self.enabled?(context)
      return true if context[:entity]&.is_a?(Repository)
      return true if context[:gist]
      return true if context[:subject]&.is_a?(GistComment)
      false
    end

    def call(node)
      # Do not override existing dir so users can customize their own HTML
      if node["dir"].nil?
        node["dir"] = "auto"
      end

      node
    end

    def selector
      SELECTOR
    end
  end
end
