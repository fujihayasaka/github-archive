# typed: true
# frozen_string_literal: true

module PullRequests
  class TipView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include TipsHelper
    include PlatformHelper

    attr_reader :pull_request

    def initialize(pull_request)
      @pull_request = pull_request
    end

    def tips
      tips = [
        "Add comments to specific lines under <a class='Link--inTextBlock' href='#{pull_request_files_changed_path}'>Files changed</a>.", # rubocop:disable Rails/ViewModelHTML
        "Add <a class='Link--inTextBlock' href='#{pull_request_patch_path}'>.patch</a> or <a class='Link--inTextBlock' href='#{pull_request_diff_path}'>.diff</a> to the end of URLs for Git’s plaintext views.", # rubocop:disable Rails/ViewModelHTML
      ]
    end

    def pull_request_url
      @pull_request.permalink(include_host: false)
    end

    def pull_request_files_changed_path
      "#{pull_request_url}/files"
    end

    def pull_request_patch_path
      "#{pull_request_url}.patch"
    end

    def pull_request_diff_path
      "#{pull_request_url}.diff"
    end

    def selected_tip
      render_link(tips.sample)
    end
  end
end
