# typed: true
# frozen_string_literal: true

module Actions
  module Runners
    class DeleteModalComponent < ApplicationComponent

      def initialize(owner_settings:, runner_id:, runner_os:, token:)
        @owner_settings = owner_settings
        @runner_id = runner_id
        @runner_os = runner_os
        @token = token
      end

      def shell
        return "powershell" if @runner_os == "windows"
        "shell"
      end

      def command
        if @runner_os == "windows"
          "./config.cmd remove --token #{@token}"
        else
          "./config.sh remove --token #{@token}"
        end
      end
    end
  end
end
