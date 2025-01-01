# typed: strict
# frozen_string_literal: true

module Settings
  class SecurityAnalysisGhasTrialComponent < ApplicationComponent
    extend T::Sig
    include AdvancedSecurityEntrypointHelper
    include ApplicationComponent::Rescuable

    rescue_from StandardError, with: :nothing

    sig { returns(T.nilable(::Organization)) }
    attr_reader :organization

    sig { returns(T.nilable(User)) }
    attr_reader :user

    sig { params(organization: T.nilable(::Organization), user: T.nilable(User)).void }
    def initialize(organization:, user:)
      @organization = organization
      @user = user
    end

    sig { returns(T::Boolean) }
    def render?
      banner_mode != :do_not_show
    end

    sig { returns(Symbol) }
    def notice_name
      :security_analysis_ghas_trial_banner
    end

    private

    sig { returns(T::Boolean) }
    def show_self_serve_cta?
      banner_mode == :self_serve
    end

    sig { returns(Symbol) }
    memoize def banner_mode
      show_advanced_security_entrypoint?(organization: organization, user: user)
    end

  end
end
