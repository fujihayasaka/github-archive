# typed: strict
# frozen_string_literal: true

Dir["#{Rails.root}/packages/*/initializers/**/*.rb"].each do |file|
  require file
end
