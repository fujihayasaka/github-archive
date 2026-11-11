# typed: true
# frozen_string_literal: true

module Gists
  class IndexComponent < ApplicationComponent

    def initialize(gist_id:, visibility:, user_param:, repo_name:, name_with_owner:, last_maintenance_at:, maintenance_status:)
      @gist_id             = gist_id
      @user_param          = user_param
      @repo_name           = repo_name
      @name_with_owner     = name_with_owner
      @visibility          = visibility
      @last_maintenance_at = last_maintenance_at
      @maintenance_status  = maintenance_status
    end

    private

    attr_reader :gist_id, :user_param, :repo_name, :name_with_owner, :visibility, :last_maintenance_at, :maintenance_status

    def public?
      visibility == "public"
    end

    def marked_broken?
      maintenance_status == "broken"
    end

    def link
      if public?
        link_to name_with_owner, stafftools_user_gist_path(user_param, repo_name)
      else
        "private"
      end
    end
  end
end
