# typed: true
# frozen_string_literal: true

module Search
  module RepositoryActionIconHelper
    # Based on action_icon in repository_action_helper.rb
    # Returns the SVG representing the action as a string, or nil if no such svg exists.
    def svg_icon_string(icon_name, owner: nil)
      folder = "feather"

      if owner && RepositoryActions::ActionPartners::CUSTOM_ICON_PARTNERS.include?(owner.downcase)
        folder = "actions"
        icon_name = owner.downcase
      end

      path = "public/images/icons/#{folder}/#{icon_name}.svg"
      return nil unless File.file?(path)

      File.read(path)
    end
  end
end
