# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateExploreCollection < Platform::Mutations::Base
      description "Updates an existing collection."
      visibility :internal

      minimum_accepted_scopes ["site_admin"]

      argument :slug, String, "The slug of the collection.", required: true
      argument :is_featured, Boolean, "Indicates whether the collection is featured.", required: false

      field :collection, Objects::ExploreCollection, "The updated collection.", null: true

      def resolve(**inputs)
        collection = Objects::ExploreCollection.load_from_global_id(inputs[:slug]).sync
        raise Errors::NotFound.new("Invalid collection slug '#{inputs[:slug]}'") unless collection

        unless inputs[:is_featured].nil?
          unless context[:viewer].biztools_user? || context[:viewer].site_admin?
            raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to " \
                                           "change collection #{collection.slug}'s featured status.")
          end

          collection.featured = inputs[:is_featured]
        end

        if collection.save
          { collection: collection }
        else
          errors = collection.errors.full_messages.join(", ")
          raise Errors::Unprocessable.new("Could not update collection: #{errors}")
        end
      end
    end
  end
end
