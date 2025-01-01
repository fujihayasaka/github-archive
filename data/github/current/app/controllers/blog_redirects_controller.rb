# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/routes_legacy_blog_post_redirects"

class BlogRedirectsController < ApplicationController # rubocop:todo GitHub/ControllersShouldHaveTests
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:show]

  def show
    id = params.require(:id)
    if new_path = LEGACY_BLOG_POST_REDIRECTS[id.to_i]
      redirect_to("#{GitHub.blog_url}/#{new_path}/", status: 301)
    else
      render_404
    end
  end
end
