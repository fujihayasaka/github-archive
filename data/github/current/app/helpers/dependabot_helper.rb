# typed: true
# frozen_string_literal: true

module DependabotHelper
  include TextHelper

  SORT_OPTIONS = [
    { label: "Newest", query: "created-desc" },
    { label: "Oldest", query: "created-asc" },
    { label: "Recently updated", query: "updated-desc" },
    { label: "Least recently updated", query: "updated-asc" },
  ].freeze

  RESOLUTION_OPTIONS = [
    { label: "All dismissed", query: "dismissed" },
    { label: "False positive", query: "false-positive" },
    { label: "Used in tests", query: "used-in-tests" },
    { label: "Won't fix", query: "wont-fix" },
    { label: "Fixed", query: "fixed" }
  ].freeze

  SECURITY_SEVERITIES = [:CRITICAL, :HIGH, :MEDIUM, :LOW].freeze
  SEVERITIES = [:ERROR, :WARNING, :NOTE].freeze

  AUTOFIX_RULES_LANGUAGE_MAP = {
    cpp: "C++",
    cs: "C#",
    go: "Go",
    java: "Java/Kotlin",
    js: "JavaScript/TypeScript",
    py: "Python",
    rb: "Ruby",
    swift: "Swift"
  }
end
