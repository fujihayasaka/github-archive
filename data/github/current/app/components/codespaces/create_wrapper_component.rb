# typed: true
# frozen_string_literal: true

class Codespaces::CreateWrapperComponent < ApplicationComponent
  include CodespacesHelper

  attr_reader :codespace, :current_user, :target, :open_in_deeplink, :default_sku, :defer_location_assignment, :cap_filter, :at_limit, :is_spoofed_commit, :dropdown, :block

  # A caveat on `default_sku` and `defer_location_assignment`:
  # When the latter is true, the default_sku is weakly relying on the assumption that the same SKUs are available
  # in any region. With regional failover arbitrarily directing a % of creations between to a second, fallback
  # region, the region used to calculate the default SKU might differ from the one we let the server pick when
  # handling the creation POST. In Oct 2022, the SKUs don't vary across regions in prod. However, we've taken
  # steps to handle variability, with SKUs listed per region in the service APIs, and then cached by location
  # via Codespaces::Skus::Cache. If we ever do have SKUs that vary across regions, we'll need to revisit the SKU
  # preview logic here.
  def initialize(codespace:,
                 current_user:,
                 target:,
                 open_in_deeplink:,
                 default_sku: nil,
                 defer_location_assignment: false,
                 cap_filter:,
                 at_limit:,
                 is_spoofed_commit: false,
                 dropdown: true,
                 block: false
                )
    @codespace, @current_user, @target, @open_in_deeplink, @default_sku, @defer_location_assignment, @cap_filter, @at_limit, @is_spoofed_commit, @dropdown, @block =
      codespace, current_user, target, open_in_deeplink, default_sku, defer_location_assignment, cap_filter, at_limit, is_spoofed_commit, dropdown, block
  end

  def create_button_text
    if display_ref.present?
      "Create codespace on #{display_ref}"
    else
      "New codespace"
    end
  end

  private

  memoize def display_ref
    ref = codespace.ref || codespace.pull_request&.head_ref || ""
    Git::Ref.value_for_display(ref)
  end
end
