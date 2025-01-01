# typed: true
# frozen_string_literal: true

class Sponsors::BatchDeferredSponsorButtonsController < ApplicationController
  before_action :require_xhr
  before_action :sponsors_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:index]

  def index
    batch_deferred_modal_response = sponsors_button_html_by_item

    respond_to do |format|
      format.json do
        render json: batch_deferred_modal_response
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
  sig { returns T::Hash[String, String] }
  def sponsors_button_html_by_item
    items.each_with_object({}) do |(item, inputs), hash|
      hash[item] = if inputs.has_funding_file?
        render_funding_modal_to_string(inputs)
      else
        render_sponsor_button_to_string(inputs)
      end
    end
  end

  sig { params(inputs: BatchDeferredSponsorButton).returns(T.nilable(String)) }
  def render_funding_modal_to_string(inputs)
    render_to_string(Sponsors::Repositories::FundingModalComponent.new(
      owner_login: inputs.sponsorable_login || "",
      repo_name: inputs.repo_name.to_s,
    ), layout: false)
  rescue ActionController::UrlGenerationError
    nil
  end

  sig { params(inputs: BatchDeferredSponsorButton).returns(T.nilable(String)) }
  def render_sponsor_button_to_string(inputs)
    render_to_string(Sponsors::SponsorButtonComponent.new(
      sponsorable: inputs.sponsorable_login,
      is_sponsoring: is_sponsoring_by_sponsorable_id[inputs.sponsorable_id.to_i],
      location: inputs.location&.to_sym,
    ), layout: false)
  rescue ActionController::UrlGenerationError
    nil
  end

  sig { returns T::Hash[String, BatchDeferredSponsorButton] }
  memoize def items
    # Expected parameter format:
    # {"item-0"=>
    #     {"sponsorable_login"=>"", "sponsorable_id"=>"", "location"=>"", has_funding_file"=>"", "repo_name"=>""},
    #  "item-1"=>
    #     {"sponsorable_login"=>"", "sponsorable_id"=>"", "location"=>"", has_funding_file"=>"", "repo_name"=>""},
    #    ...
    #   }
    item_params = params[:items] ? params[:items].permit!.to_h : {}

    data_pairs = item_params.map do |key, data|
      value = BatchDeferredSponsorButton.new(
        sponsorable_login: data[:sponsorable_login],
        sponsorable_id: data[:sponsorable_id],
        location: data[:location],
        has_funding_file: data[:has_funding_file],
        repo_name: data[:repo_name],
      )
      [key, value]
    end
    data_pairs.to_h
  end

  sig { returns T::Hash[Integer, T.nilable(T::Boolean)] }
  memoize def is_sponsoring_by_sponsorable_id
    return Hash.new(false) unless logged_in?

    sponsorable_ids = items.values.map(&:sponsorable_id)
    sponsoring_checker = Platform::Loaders::IsSponsoringCheck.new(current_user.id, viewer: current_user)
    sponsoring_checker.fetch(sponsorable_ids)
  end

  sig { returns T.any(User, Symbol) }
  def target_for_conditional_access
    current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
