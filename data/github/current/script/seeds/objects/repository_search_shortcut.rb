# typed: true
# frozen_string_literal: true

# Do not require anything here. If you need something else, require it in the method that needs it.
# This makes sure the boot time of our seeds stays low.

module Seeds
  module Objects
    class RepositorySearchShortcut
      def self.create(repository:, name:, query:, creator: nil, icon: nil, color: nil, description: nil, search_type: nil)
        icon = icon || ::RepositorySearchShortcut.icons.keys.sample
        color = color || ::RepositorySearchShortcut.colors.keys.sample

        attrs = {
          repository: repository,
          creator: creator,
          name: name,
          query: query,
          icon: icon,
          color: color,
          description: description,
        }
        attrs[:search_type] = search_type if search_type

        shortcut = ::RepositorySearchShortcut.create(attrs)

        raise Objects::CreateFailed, shortcut.errors.full_messages.to_sentence unless shortcut.valid?
        shortcut
      end
    end
  end
end
