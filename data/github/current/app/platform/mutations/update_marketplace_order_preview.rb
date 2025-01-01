# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateMarketplaceOrderPreview < Platform::Mutations::Base
      description "Creates/Updates an order preview for a Marketplace user/listing"
      visibility :internal

      minimum_accepted_scopes ["repo"]

      argument :user_id, Integer, "The user's database ID.", required: true
      argument :marketplace_listing_id, Integer, "The Marketplace listing's database ID.", required: true
      argument :account_id, Integer, "The target account's database ID.", required: true
      argument :marketplace_listing_plan_id, Integer, "The Marketplace listing plan's database ID.", required: true
      argument :quantity, Integer, "The order quantity.", required: true
      argument :viewed_at, Scalars::DateTime, "The timestamp the user viewed the order.", required: true

      field :marketplace_order_preview, Objects::MarketplaceOrderPreview, "The most recent order preview", null: true

      def resolve(**inputs)
        binds = {
          user_id: inputs[:user_id],
          marketplace_listing_id: inputs[:marketplace_listing_id],
          account_id: inputs[:account_id],
          marketplace_listing_plan_id: inputs[:marketplace_listing_plan_id],
          quantity: inputs[:quantity],
          viewed_at: inputs[:viewed_at],
        }

        insert = %Q(
          INSERT IGNORE INTO marketplace_order_previews
            (
              account_id,
              user_id,
              marketplace_listing_id,
              marketplace_listing_plan_id,
              quantity,
              viewed_at,
              created_at,
              updated_at
            )
          VALUES
            (
              :account_id,
              :user_id,
              :marketplace_listing_id,
              :marketplace_listing_plan_id,
              :quantity,
              :viewed_at,
              now(),
              now()
            )
        )

        update = %Q(
          UPDATE marketplace_order_previews SET
            account_id = :account_id,
            marketplace_listing_plan_id = :marketplace_listing_plan_id,
            quantity = :quantity,
            updated_at = now(),
            viewed_at = :viewed_at
          WHERE
            user_id = :user_id AND marketplace_listing_id = :marketplace_listing_id AND viewed_at <= :viewed_at
        )

        Marketplace::OrderPreview.connection.insert(Arel.sql(insert, **binds))
        Marketplace::OrderPreview.connection.update(Arel.sql(update, **binds))

        { marketplace_order_preview: Marketplace::OrderPreview.find_by(user_id: inputs[:user_id], marketplace_listing_id: inputs[:marketplace_listing_id]) }
      end
    end
  end
end
