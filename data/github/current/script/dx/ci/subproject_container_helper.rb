# frozen_string_literal: true

require "json"
require "open3"
require "optparse"

def get_changed_files
  head_ref = ENV["HEAD_REF"]
  base_ref = ENV["BASE_REF"]

  if head_ref.nil? || head_ref.empty? || base_ref.nil? || base_ref.empty?
    raise ArgumentError, "HEAD_REF and BASE_REF environment variables must be set."
  end

  fetch_cmd = "git fetch --depth=1 origin #{base_ref}"
  stdout, stderr, status = Open3.capture3(fetch_cmd)
  if !status.success?
    raise RuntimeError, "ERROR: unable to `git fetch` branches #{base_ref}. We suggest you retry the job."
  end

  files_changed_cmd = "git diff --name-only origin/#{base_ref}"

  stdout, stderr, status = Open3.capture3(files_changed_cmd)
  if !status.success?
    STDERR.puts "`git diff` error files changed between #{head_ref} and #{base_ref}"
    STDERR.puts "Stderr: #{stderr}"
    STDERR.puts "#{files_changed_cmd}"
    raise RuntimeError, "ERROR: unable to `git diff` files changed between #{head_ref} and #{base_ref}. We suggest you retry the job."
  end
  puts "The files changed between #{base_ref} and #{head_ref} are: \n#{stdout}\n"

  files_changed = stdout.split(/\n/)

  files_changed
end

def sha_from_file(file)
  sha = nil
  File.open(file) { |sha_file|
    sha_file.each_line do |line|
      # Some version files have comments, this ignores any lines that are comments
      stripped_line = line.strip

      if /\b([a-f0-9]{40})\b/.match?(stripped_line)
        sha = stripped_line
      end
    end
  }

  sha
end
