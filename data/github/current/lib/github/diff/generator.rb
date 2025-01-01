# typed: false
# frozen_string_literal: true

require "diff/lcs/hunk"

# Diff::Generator can be used to produce String unified diffs.
#
# This code:
#
#   GitHub::Diff::Generator.diff("file.rb",
#     "def say(word)\nputs thing\nend",
#     "def say(word)\nputs word\nend")
#
# returns this string:
#
#   --- a/file.rb
#   +++ b/file.rb
#   @@ -1,4 +1,4 @@
#    def say(word)
#   -puts thing
#   +puts word
#    end
#
module GitHub::Diff::Generator
  extend self

  # Uses Diff::LCS to produce a unified diff.
  #
  # path  - String path to the file, e.g. "lib/mustache.rb"
  # fileA - The original String contents of the file.
  # fileB - The modified String contents of the file.
  #
  # Returns a String in unified diff format.
  def diff(path, fileA, fileB, lines: 3)
    patch = +""

    format = :unified
    output = +""
    file_length_difference = 0

    data_old = fileA.split(/\n/).map! { |e| e.chomp }
    data_new = fileB.split(/\n/).map! { |e| e.chomp }

    diffs = Diff::LCS.diff(data_old, data_new)
    return "" if diffs.empty?

    a_path = "a/#{path.gsub('./', '')}"
    b_path = "b/#{path.gsub('./', '')}"

    header = "--- #{a_path}"
    header << "\n+++ #{b_path}"
    header += "\n"

    oldhunk = hunk = nil

    diffs.each do |piece|
      begin
        hunk = Diff::LCS::Hunk.new(data_old, data_new, piece, lines,
          file_length_difference)
        file_length_difference = hunk.file_length_difference

        next unless oldhunk

        if lines > 0 && hunk.overlaps?(oldhunk)
          hunk.unshift(oldhunk)
        else
          output << oldhunk.diff(format)
          output << "\n"
        end
      ensure
        oldhunk = hunk
      end
    end

    output << oldhunk.diff(format)
    output << "\n"

    patch << header + output.lstrip

    patch
  rescue # rubocop:todo Lint/GenericRescue
    "" # something was bad or lcs isn't there - no diff
  end
end
