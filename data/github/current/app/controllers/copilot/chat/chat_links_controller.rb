# typed: true
# frozen_string_literal: true

class Copilot::Chat::ChatLinksController < Copilot::Chat::AbstractChatController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    return head :not_found unless chat_link_item.item

    render json: chat_link_item.reference
  end

  private

  sig { returns Copilot::ChatLinkItem }
  memoize def chat_link_item
    Copilot::ChatLinkItem.new(item_url, current_user)
  end

  sig { returns T.nilable(String) }
  def item_url
    return nil unless params[:item_url]

    uri = URI.parse(params[:item_url])
    T.must(uri.path)[1..-1]
  end

  def target_for_conditional_access
    chat_link_item.conditional_access_item&.target_for_conditional_access
  end

  def resource_for_conditional_access
    chat_link_item.conditional_access_item || :no_resource_for_conditional_access # rubocop:todo GitHub/SpecifyResourceForConditionalAccess
  end
end
