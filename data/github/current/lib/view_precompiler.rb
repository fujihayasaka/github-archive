# typed: true
# frozen_string_literal: true

class ViewPrecompiler
  def self.precompile
    ActionviewPrecompiler.precompile do |precompiler|
      ActionController::Base.view_paths.each do |view_path|
        precompiler.scan_view_dir view_path.path
      end

      Rails.application.paths["app/controllers"].each do |path|
        precompiler.scan_controller_dir path.to_s
      end

      Dir.glob("packages/*/app/controllers/").each do |path|
        precompiler.scan_controller_dir path.to_s
      end

      Rails.application.paths["app/helpers"].each do |path|
        precompiler.scan_helper_dir path.to_s
      end
    end
  end
end
