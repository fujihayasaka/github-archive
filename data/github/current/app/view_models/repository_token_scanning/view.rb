# typed: true
# frozen_string_literal: true

module RepositoryTokenScanning
  class View < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include GitHub::TokenScanning::SecretScanningHelper

    attr_reader :repository, :current_page, :page_size

    def resolution_description(resolution)
      case resolution
      when "revoked" then "revoked"
      when "false_positive" then "false positive"
      when "used_in_tests" then "used in tests"
      when "wont_fix" then "won't fix"
      when "pattern_deleted" then "pattern deleted"
      when "pattern_edited" then "pattern edited"
      when "hidden_by_config" then "ignored by configuration"
      end
    end

    def resolutions
      {
        revoked: "Revoked",
        false_positive: "False positive",
        used_in_tests: "Used in tests",
        wont_fix: "Won't fix",
      }
    end

    def resolve_path(resolution:, id: nil)
      urls.repository_token_scanning_resolve_path(repository.owner, repository, resolution: resolution, id: id)
    end
  end
end
