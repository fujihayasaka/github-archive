# typed: true
# frozen_string_literal: true

module CodeScanning
  module ControllerAccessChecks
    extend T::Helpers

    requires_ancestor { ApplicationController }

    def check_code_scanning_read
      render_404 unless current_repository.code_scanning_readable_by?(current_user)
    end

    def check_code_scanning_write
      render_404 unless current_repository.code_scanning_writable_by?(current_user)
    end
  end
end
