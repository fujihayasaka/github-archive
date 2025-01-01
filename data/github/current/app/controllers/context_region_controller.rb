# typed: true
# frozen_string_literal: true

class ContextRegionController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:show]

  def show
    respond_to do |format|
      format.html do
        # The compact (mobile) version of the context region is too complex to reliably update client-side,
        # so the front-end can just ask for a new server-rendered version when it needs to be updated.
        if params[:variant] == "compact"
          render Site::Header::CompactContextRegionComponent.new(context_items, current_path), layout: false
        elsif params[:variant] == "overflow"
          render Site::Header::ContextRegion::ResponsiveOverflowMenuComponent.new(context_items), layout: false
        end
      end
    end
  end

  private

  def context_items
    crumbs_json = params[:crumbs] || "[]"
    context_item_json = JSON.parse(crumbs_json)

    context_item_json.map do |item|
      ContextRegion::BasicCrumb.new(nil, label: item["label"], path: item["href"], dom_id: item["crumbId"])
    end
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
