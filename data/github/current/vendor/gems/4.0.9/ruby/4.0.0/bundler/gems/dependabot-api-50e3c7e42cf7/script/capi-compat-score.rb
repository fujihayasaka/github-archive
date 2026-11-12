#!/usr/bin/env ruby
# frozen_string_literal: true

require "openssl"
require "time"
require "excon"
require "json"
require "erb"
require_relative "../lib/copilot"

hmac_key = ENV["CAPI_HMAC_DEV_KEY"]
github_user = ENV["GITHUB_USER"] || "749864" # @jurre

template_path = "script/copilot-prompts/compat-score.md.erb"
erb_template = File.read(template_path)
erb = ERB.new(erb_template)

prompt = erb.result_with_hash({
                                dependency_name: "rubocop",
                                from_version: "1.0.0",
                                to_version: "2.0.0",
                              })

copilot = Copilot::API.new(hmac_key, github_user)
completion = copilot.create_completion(prompt: prompt)

puts completion.text # rubocop:disable Rails/Output
