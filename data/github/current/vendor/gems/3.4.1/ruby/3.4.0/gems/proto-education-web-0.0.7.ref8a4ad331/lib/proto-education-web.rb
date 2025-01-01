# frozen_string_literal: true

require "proto/education-web/version"

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "proto", "education-web")

Dir["#{File.dirname(__FILE__)}/**/*_twirp.rb"].each { |file| require file }
