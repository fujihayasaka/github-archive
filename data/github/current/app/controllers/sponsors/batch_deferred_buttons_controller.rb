# typed: true
# frozen_string_literal: true

class Sponsors::BatchDeferredButtonsController < ApplicationController
  before_action :login_required
  before_action :require_xhr
  before_action :sponsors_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:batch]

  def batch # rubocop:todo GitHub/UseRestfulActions
    batch_deferred_buttons_response = sponsors_button_html_by_item

    respond_to do |format|
      format.json do
        render json: batch_deferred_buttons_response
      end
    end
  end

  private

  # Private: Prepares Hash of item and its HTML content expected by
  # BatchDeferredContent. See https://github.com/orgs/github/teams/engineering/discussions/301
  #
  # Returns Hash of format
  #  {"item-0"=>
  #    "<html ...>",
  #   "item-1"=>
  #    "<html ...>",
  #   ...
  #  }
  def sponsors_button_html_by_item
    items.each_with_object({}) do |(item, inputs), hash|
      sponsorable_login = inputs[:sponsorable_login]
      sponsorable_id = inputs[:sponsorable_id].to_i
      is_sponsoring = is_sponsoring_by_sponsorable_id[sponsorable_id]
      location = inputs[:location].to_sym

      hash[item] = render_to_string(Sponsors::SponsorButtonComponent.new(
          sponsorable: sponsorable_login,
          is_sponsoring: is_sponsoring,
          location: location,
        )
      )
    end
  end

  # Private: Returns expected items from BatchDeferredContent via parmas of format:
  #   {"item-0"=>
  #     {"sponsorable_login"=>"", "sponsorable_id"=>"", "location"=>""},
  #    "item-1"=>
  #     {"sponsorable_login"=>"", "sponsorable_id"=>"", "location"=>""},
  #    ...
  #   }
  def items
    return {} unless params[:items]
    params[:items].permit!.to_h
  end

  def sponsorable_ids
    inputs = items.values
    inputs.map { |input| input[:sponsorable_id] }
  end

  def sponsoring_checker
    Platform::Loaders::IsSponsoringCheck.new(
      current_user.id,
      viewer: current_user
    )
  end

  def is_sponsoring_by_sponsorable_id
    @is_sponsoring_by_sponsorable_id if defined?(@is_sponsoring_by_sponsorable_id)

    @is_sponsoring_by_sponsorable_id = sponsoring_checker.fetch(sponsorable_ids)
  end

  def target_for_conditional_access
    current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
