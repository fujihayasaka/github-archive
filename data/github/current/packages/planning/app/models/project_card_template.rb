# typed: true
# frozen_string_literal: true

# A simple object used by ProjectTemplate to create column templates
#
# See ProjectTemplate for usage instructions :sparkles:
#
class ProjectCardTemplate
  attr_reader :note

  def initialize(note:)
    @note = note
  end

  # Returns a list of card data in priority order for creating ProjectCardTemplates.
  # Cards are returned in reverse order so they are prioritized correctly;
  # priority is set based on order added, where newest has highest priority.
  def self.all_prioritized
    CARDS.reverse.map { |card| new(**card) }
  end

  CARDS = [
    { note:
      <<~HEREDOC,
      :sparkles: **Welcome to GitHub projects** :sparkles:
      We're so excited that you've decided to create a new project! Now that you're here, let's make sure you know how to get the most out of GitHub projects.
      - [x] Create a new project
      - [x] Give your project a name
      - [ ] Press the <kbd>?</kbd> key to see available keyboard shortcuts
      - [ ] Add a new column
      - [ ] Drag and drop this card to the new column
      - [ ] Search for and add issues or PRs to your project
      - [ ] Manage automation on columns
      - [ ] [Archive a card](#{GitHub.help_url}/articles/archiving-cards-on-a-project-board/) or archive all cards in a column
    HEREDOC
    },
    { note:
      <<~HEREDOC,
      **Cards**
      Cards can be added to your board to track the progress of issues and pull requests. You can also add note cards, like this one!
    HEREDOC
    },
    { note:
      <<~HEREDOC,
      **Automation**
      [Automatically move your cards](#{GitHub.help_url}/articles/configuring-automation-for-project-boards/) to the right place based on the status and activity of your issues and pull requests.
    HEREDOC
    },
  ].freeze
end
