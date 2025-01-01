# typed: strict
# frozen_string_literal: true
module Codespaces
  class ToggleFailoverJob < CodespacesJob

    locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    sig { override.params(region: String, vscs_target: Symbol, redirect: T::Boolean, only: T.nilable(String), codespaces_repository: T.nilable(Repository), actor: T.nilable(String), percent: T.nilable(Integer)).void }
    def perform(region:, vscs_target:, redirect:, only:, codespaces_repository:, actor:, percent: nil)
      stamp = Codespaces::VscsServiceStamp.find(region:, vscs_target:)
      ToggleFailover.call(stamp:, redirect:, only:, codespaces_repository:, actor:, percent:)
    end
  end
end
