# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Contribution
      include Interfaces::Base
      description "Represents a contribution a user made on GitHub, such as opening an issue."

      field :user, Objects::User, null: false, description: <<~DESCRIPTION
        The user who made this contribution.
      DESCRIPTION

      url_fields description: "The HTTP URL for this contribution." do |contrib|
        from = contrib.occurred_at.beginning_of_month.strftime("%Y-%m-%d")
        to = contrib.occurred_at.end_of_month.strftime("%Y-%m-%d")
        template = Addressable::Template.new("/{user}?tab=overview&from={from}&to={to}")
        template.expand(user: contrib.user.display_login, from: from, to: to)
      end

      field :occurred_at, Scalars::DateTime, null: false,
        description: "When this contribution was made."

      field :is_restricted, Boolean, null: false, method: :restricted?, description: <<~DESCRIPTION
        Whether this contribution is associated with a record you do not have access to. For
        example, your own 'first issue' contribution may have been made on a repository you can no
        longer access.
      DESCRIPTION

    end
  end
end
