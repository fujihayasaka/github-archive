# typed: true
# frozen_string_literal: true

module RepositoriesTypeHelper
  def self.type(visibility:, mirror:, archived:, template:)
    visibility_label = visibility.capitalize # Public, Private, or Internal
    if visibility.downcase == "public" && mirror
      "Public mirror"
    elsif archived
      "#{visibility_label} archive"
    elsif template
      "#{visibility_label} template"
    else
      visibility_label
    end
  end
end
