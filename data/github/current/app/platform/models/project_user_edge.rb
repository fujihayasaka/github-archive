# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectUserEdge < GraphQL::Pagination::Connection::Edge
  def permission
    Platform::Loaders::DirectProjectUserAbilities.load(project: parent, user: node).then do |ability|
      # This will throw an exception if null since this field is not nullable
      # In theory this should never happen because the user should have
      # access to this project by virtue of it being in this list.
      # Leaving this exception here so we get alerted if this happens
      ability.action.to_s
    end
  end
end
