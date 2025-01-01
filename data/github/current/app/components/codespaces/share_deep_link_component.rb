# typed: true
# frozen_string_literal: true

module Codespaces
  class ShareDeepLinkComponent < ApplicationComponent
    include ResilienceHelper
    include CodespacesHelper
    include BranchesHelper
    include HydroHelper

    attr_reader :codespace

    BASE_URL = "https://codespaces.new"
    REPO_TEMPLATE = BASE_URL + "/{owner}/{name}"
    BRANCH_TEMPLATE = REPO_TEMPLATE + "/tree/{branch}"
    PR_TEMPLATE = REPO_TEMPLATE + "/pull/{pull_number}"

    def initialize(codespace:)
      @codespace = codespace
    end

    def is_template_repository?
      @codespace.repository.template?
    end

    def initial_branch_ref
      return nil unless @codespace.branch.present?
      with_database_error_fallback do
        Codespaces::GetTargetRef.call(repository: @codespace.repository, name_or_oid: @codespace.branch)
      end
    end

    memoize def devcontainers
      oid = initial_branch_ref&.target_oid
      Codespaces::DevContainer.list_dev_containers(@codespace.repository, oid)
    end

    def active_devcontainer
      devcontainers&.first
    end

    def url_template
      template = with_database_error_fallback(fallback: REPO_TEMPLATE) do
        if codespace.pull_request.present?
          PR_TEMPLATE
        elsif codespace.display_branch != codespace.repository.default_branch
          BRANCH_TEMPLATE
        else
          REPO_TEMPLATE
        end
      end
      Addressable::Template.new(template + "{?query*}")
    rescue GitHub::Spokes::ClientError
      Addressable::Template.new(REPO_TEMPLATE + "{?query*}")
    end

    def url_text
      url_template.expand(
        owner: codespace.repository.owner_display_login,
        name: codespace.repository.to_s,
        branch: codespace.display_branch,
        pull_number: codespace.pull_request&.number).to_s
    end

    memoize def url_click_tracking_attributes
      click_tracking_attributes("URL")
    end

    memoize def html_click_tracking_attributes
      click_tracking_attributes("HTML")
    end

    memoize def markdown_click_tracking_attributes
      click_tracking_attributes("MARKDOWN")
    end

    def click_tracking_attributes(share_type)
      payload = {
        repository_id: codespace.repository_id,
        share_type: share_type,
        user_id: current_user&.id
      }
      hydro_click_tracking_attributes("codespace_share.click", payload)
    end
  end
end
