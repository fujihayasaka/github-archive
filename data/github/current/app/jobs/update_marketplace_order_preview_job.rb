# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UpdateMarketplaceOrderPreviewJob < ApplicationJob
  queue_as :marketplace
  retry_on_dirty_exit

  # Create or update an order preview/cart for the specified user/listing.
  #
  # It's possible that order preview updates may run out of order as a user changes
  # accounts/plans/etc. - so only update older information.
  def perform(user_id, listing_id, account_id, plan_id, quantity, viewed_at)
    viewer = User.find_by(id: user_id)
    variables = {
      input: {
        "userId" => user_id,
        "marketplaceListingId" => listing_id,
        "accountId" => account_id,
        "marketplaceListingPlanId" => plan_id,
        "quantity" => quantity,
        "viewedAt" => Time.at(viewed_at).iso8601,
      },
    }

    listing = Marketplace::Listing.find_by(id: listing_id)
    listing_plan = listing.listing_plans.find_by(id: plan_id) if listing

    if listing&.publicly_listed? && listing_plan&.published?
      with_write do
        Platform.execute(
          UpdateMarketplaceOrderPreviewMutation,
          target: :internal,
          context: { viewer: viewer },
          variables: variables,
        )
      end
    end
  end

  UpdateMarketplaceOrderPreviewMutation = <<-'GRAPHQL'
    mutation($input: UpdateMarketplaceOrderPreviewInput!) {
      updateMarketplaceOrderPreview(input: $input) {
        __typename
      }
    }
  GRAPHQL
end
