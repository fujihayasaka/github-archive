# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class Reaction < Connections::Base
      description "A list of reactions that have been left on the subject."

      total_count_field

      field :viewer_has_reacted, Boolean, description: "Whether or not the authenticated user has left a reaction on the subject.", null: false

      def viewer_has_reacted
        if @context[:viewer]
          @object.items.where(user_id: @context[:viewer].id).exists?
        else
          false
        end
      end
    end
  end
end
