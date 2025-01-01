# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Plan < Platform::Objects::Base
      description "The billing plan associated with a user or organization"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        #FIXME
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      visibility :internal

      minimum_accepted_scopes ["user"]

      field :name, String, "The internal name of the plan.", null: false
      field :display_name, String, "The display name of the plan.", null: false
      field :is_business, Boolean, "Is the plan the business plan?", method: :business?, null: false
      field :is_business_plus, Boolean, "Is the plan the business plus plan?", method: :business_plus?, null: false
      field :is_per_seat, Boolean, "Is the plan per seat or per repo." , method: :per_seat?, null: false
      field :is_pro, Boolean, "Is the plan the pro plan?", method: :pro?, null: false

      field :allowed_private_repositories_count, Integer, "The number of private repositories allowed in the plan.", method: :repos, null: false

      field :allowed_disk_size, Integer, description: "The size in kilobytes made available in the plan.", null: false

      def allowed_disk_size
        @object.space / 1.kilobyte
      end
    end
  end
end
