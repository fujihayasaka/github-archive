# typed: true
# frozen_string_literal: true

require "faraday"

module FeedPosts
  class EmbedsController < ApplicationController
    before_action :login_required
    before_action :require_feature_enabled

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Repositories

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:show],
      optional: true

    def show
      url = CGI.unescape(params[:url])
      result = scanner.new(url).scan

      respond_to do |format|
        format.html do
          render ::FeedPosts::EmbedComponent.new(result:), layout: false
        end
      end
    end

    private

    def scanner
      if user_or_global_feature_enabled?(:open_graph_external_url)
        OpenGraph::Scanner
      else
        OpenGraph::Internal::Scanner
      end
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_user
    end

    def require_feature_enabled
      render_404 unless user_or_global_feature_enabled?(:feed_post_embeds)
    end
  end
end
