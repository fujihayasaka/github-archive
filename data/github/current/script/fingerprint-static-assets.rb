#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "pathname"
require "find"
require "set"

class FingerprintStaticAssets
  def initialize
    @manifest = {}
    @root_path = File.expand_path("..", __dir__)
    @public_path = File.join(@root_path, "public")
    @assets_path = File.join(@root_path, "public", "assets")
    @destination_path = File.join(@root_path, ENV["DESTINATION"] || "public/assets")
    @manifest_path = File.join(@destination_path, "manifest.static.json")
  end

  def hash_file(path)
    unless File.readable?(path)
      raise "Tried to read #{path} but the file could not be accessed due to permission issues."
    end

    begin
      # Read file as binary first, then force UTF-8 encoding with replacement characters
      # This matches Node.js behavior when reading binary files with 'utf-8' encoding
      binary_contents = File.read(path, mode: "rb")
      # Force UTF-8 encoding and replace invalid sequences (like Node.js does)
      contents = binary_contents.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "\ufffd")
    rescue StandardError => e
      raise "Failed to read #{path}: #{e.message}"
    end

    Digest::SHA512.hexdigest(contents)[0, 12]
  end

  def fingerprint_assets
    # Get all files in public/ excluding assets/ (using same logic as TypeScript)
    # TypeScript uses: globFromRoot(`${publicPath}/**`, { ignore: `${assetsPath}/**`, nodir: true, follow: true })

    # Get the normalized assets path for comparison
    assets_path_normalized = File.expand_path(@assets_path) + File::SEPARATOR

    assets = []

    # First, get all files normally (without following symlinks)
    Find.find(@public_path) do |path|
      # Only include files (not directories)
      next unless File.file?(path)

      # Skip files in the assets directory
      expanded_path = File.expand_path(path)
      next if expanded_path.start_with?(assets_path_normalized)

      # Skip hidden files (files starting with .)
      basename = File.basename(path)
      next if basename.start_with?(".")

      assets << path
    end

    # Then manually add files from symlinked directories
    # This matches how the TypeScript glob with follow: true works
    Dir.glob(File.join(@public_path, "*")).each do |item|
      if File.symlink?(item) && File.directory?(item)
        symlink_target = File.readlink(item)

        # Handle relative symlinks
        unless symlink_target.start_with?("/")
          symlink_target = File.join(File.dirname(item), symlink_target)
        end

        # Find all files in the symlinked directory
        if File.directory?(symlink_target)
          Find.find(symlink_target) do |symlinked_file|
            next unless File.file?(symlinked_file)

            # Skip files in assets directory
            expanded_path = File.expand_path(symlinked_file)
            next if expanded_path.start_with?(assets_path_normalized)

            # Skip hidden files (files starting with .)
            basename = File.basename(symlinked_file)
            next if basename.start_with?(".")

            # Create the path as it appears through the symlink
            relative_path = Pathname.new(symlinked_file).relative_path_from(Pathname.new(symlink_target))
            symlinked_path = File.join(item, relative_path)

            assets << symlinked_path
          end
        end
      end
    end

    assets.sort!

    assets.each do |asset|
      hash = hash_file(asset)
      ext = File.extname(asset)
      name = File.basename(asset, ext)

      # Get relative path from public directory (matching TypeScript: relative(publicPath, asset))
      asset_path = Pathname.new(File.expand_path(asset))
      public_path_obj = Pathname.new(File.expand_path(@public_path))
      relative_path = asset_path.relative_path_from(public_path_obj).to_s

      @manifest[relative_path] = "#{name}-#{hash}#{ext}"
    end
  end

  def write_manifest
    FileUtils.mkdir_p(@destination_path) unless Dir.exist?(@destination_path)
    File.write(@manifest_path, JSON.pretty_generate(@manifest))
  end

  def copy_fingerprinted_files
    @manifest.each do |original_path, fingerprinted_name|
      source_path = File.join(@public_path, original_path)
      destination_path = File.join(@destination_path, fingerprinted_name)
      FileUtils.cp(source_path, destination_path)
    end
  end

  def run
    puts "Starting fingerprint static assets process..."
    puts "Public path: #{@public_path}"
    puts "Destination path: #{@destination_path}"

    fingerprint_assets
    puts "Found #{@manifest.size} assets to fingerprint"

    write_manifest
    puts "Wrote manifest to #{@manifest_path}"

    copy_fingerprinted_files
    puts "Successfully fingerprinted and copied #{@manifest.size} static assets"
  rescue StandardError => error
    # log a formatted error for build pipelines to pick up
    puts "===ERROR==="
    puts JSON.pretty_generate({ error: error.to_s })
    puts "===END ERROR==="

    # log an unformatted error to get full stacktrace in the logs
    $stderr.puts error.full_message

    # Exit with a non-zero exit code so the ci job fails
    exit 1
  end
end

if __FILE__ == $0
  begin
    FingerprintStaticAssets.new.run
  rescue => error
    # Log formatted error for build pipelines to pick up
    puts "===ERROR==="
    puts JSON.pretty_generate({ error: error.message })
    puts "===END ERROR==="

    # Log unformatted error to get full stacktrace in the logs
    puts error.full_message

    # Exit with non-zero exit code so the ci job fails
    exit 1
  end
end
