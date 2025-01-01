# typed: true
# frozen_string_literal: true

Dir.glob("#{Rails.root.join("lib/gh/interfaces/*")}").sort.each do |file|
  require file
end
