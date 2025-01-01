# frozen_string_literal: true

Dir[File.expand_path("../../subscribers/**/*.rb", __FILE__)].each do |file|
  require file
end
