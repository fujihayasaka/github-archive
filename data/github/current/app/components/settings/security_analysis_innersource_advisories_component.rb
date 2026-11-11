# typed: true
# frozen_string_literal: true

module Settings
  class SecurityAnalysisInnersourceAdvisoriesComponent < ApplicationComponent
    include GitHub::Memoizer
    include SecurityAnalysisSettingsHelper

    sig { returns(T.any(::Organization, ::Business, ::User)) }
    attr_reader :owner

    sig { returns(Integer) }
    attr_reader :private_repo_count

    sig { returns(BlockedSettings) }
    attr_reader :blocked_settings

    # TODO: owner can be Organizaiton, Business, or User. We should figure out how to type this without causing issues.
    sig { params(owner: T.any(::Organization, ::Business, ::User), private_repo_count: Integer, blocked_settings: T.nilable(BlockedSettings)).void }
    def initialize(owner:, private_repo_count:, blocked_settings: nil)
      @owner = owner
      @private_repo_count = private_repo_count
      @blocked_settings = T.let(blocked_settings || BlockedSettings.new(owner), BlockedSettings)
    end

    sig { returns(T::Boolean) }
    def render?
      # If owner is not an instance org, the second half of the conditional will not execute.
      owner.instance_of?(::Organization) && AdvisoryDB::Innersource.org_authorized?(org: T.cast(owner, ::Organization))
    end

    sig { returns(String) }
    def security_analysis_update_path
      settings_org_security_analysis_update_path(owner, owner: owner)
    end

    sig { returns(T::Boolean) }
    def disable_button?
      blocked_settings.innersource_advisories? ||
        !AdvisoryDB::Innersource.org_authorized?(org: T.cast(owner, ::Organization)) ||
        private_repo_count <= 0
    end

    # Returns a title for the button depending on if the button is enabled/disabled and its context.
    sig { params(default_title: String).returns(String) }
    def button_title(default_title)
      if blocked_settings.innersource_advisories?
        "Enabling other services"
      elsif !AdvisoryDB::Innersource.org_authorized?(org: T.cast(owner, ::Organization))  # Does not currently render if owner is not an org
        "Your organization is not authorized for this feature"
      elsif private_repo_count <= 0
        "No applicable repositories"
      else
        default_title
      end
    end
  end
end
