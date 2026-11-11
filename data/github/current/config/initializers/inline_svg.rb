# frozen_string_literal: true

module InlineSvg
  class FilesystemInlineSvgLoader
    attr_reader :assets, :paths

    def initialize(paths: [])
      @paths = Array(paths).compact.map { |p| Pathname.new(p) }
      @files = find_files unless GitHub.lazy_find_inline_svg_files?
      @asset_file_map = {}
    end

    def reload!
      @files = nil
      @asset_file_map = {}
    end

    def named(asset_name)
      file = filename_lookup(asset_name)
      if file
        File.read(file)
      else
        raise InlineSvg::AssetFile::FileNotFound.new("Asset not found: #{asset_name}")
      end
    end

    private

    def find_files
      @paths.map { |path| find_assets(path) }
        .inject([], :+)
        .sort_by(&:length)
        .reverse
    end

    def find_assets(path)
      acc = []
      path.glob("**/*.svg").each do |file|
        if file.readable_real?
          acc << file.to_s
        end
      end
      acc
    end

    def filename_lookup(asset_name)
      @files ||= find_files

      @asset_file_map[asset_name] ||= @files.detect { |file| file.include?(asset_name) }
    end
  end
end

InlineSvg.configure do |config|
  dirs = [
    "#{Rails.root}/public/static/images/modules",
    "#{Rails.root}/public/static/images/icons",
  ]

  # Cache SVG paths at boot time for performance
  svg_loader = InlineSvg::FilesystemInlineSvgLoader.new(
    paths: dirs
  )

  if Rails.env.development? && !ENV["FASTDEV"] && !ENV["PRELOAD"]
    # Allow SVG assets to be dynamically reloaded in development mode:
    reloader = ActiveSupport::EventedFileUpdateChecker.new([], dirs.index_with("svg")) do
      svg_loader.reload!
    end
    ActionDispatch::Callbacks.before do
      reloader.execute_if_updated
    end
  end

  config.asset_file = svg_loader
end
