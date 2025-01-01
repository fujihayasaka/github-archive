# typed: false
# frozen_string_literal: true

module Configurable
  module ArchiveProgramOptOut
    KEY = "archive_program_opt_out"

    # Public: Opts target out of the Archive Program.
    #
    # actor - User updating the setting
    #
    # Returns true if setting changed, false otherwise
    def enable_archive_program_opt_out(actor:)
      return false if archive_program_opt_out_enabled?
      config.enable(KEY, actor)
    end

    # Public: Remove opt out setting.
    #
    # Public repos are opted in to the Archive Program by default, so we can
    # opt them back in by clearing this setting.
    #
    # actor - User updating the setting
    #
    # Returns true if the setting changed, false otherwise
    def disable_archive_program_opt_out(actor:)
      return false unless archive_program_opt_out_enabled?
      config.delete(KEY, actor)
    end

    # Public: Check whether setting is enabled for target
    #
    # Returns boolean
    def archive_program_opt_out_enabled?
      can_participate_in_archive_program? && config.enabled?(KEY)
    end

    # Public: Check whether target can participate in the Archive Program
    #
    # Our TOS specifies that only public repos are eligible to participate in
    # the Archive Program. Any changes should be cleared with legal.
    #
    # Returns boolean
    def can_participate_in_archive_program?
      !GitHub.enterprise? && self.public?
    end
  end
end
