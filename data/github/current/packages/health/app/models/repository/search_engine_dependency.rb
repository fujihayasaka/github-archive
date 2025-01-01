# typed: false
# frozen_string_literal: true

module Repository::SearchEngineDependency
  # Should we be hiding this repository from Google results?
  # There are a number of reasons we might want to do this:
  #   - The repository is empty
  #   - The repo is flagged as spammy
  #   - Fork with nothing in it
  #   - Fork with only pull requests / minor changes
  #   - Stafftools revokes privilege
  #
  # Returns a Boolean
  def hide_from_google?
    return true if route.nil? || empty? # empty
    return true if spammy?
    return true if self.noindex?

    if fork?
      # If this is a fork with a different name than its root,
      # include it in Google results. Probably a new network.
      return false if name != root.name
      return true if !popular_fork?
    end

    false # let Google see it
  end
  alias :hide_from_search? :hide_from_google?

end
