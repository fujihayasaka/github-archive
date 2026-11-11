# frozen_string_literal: true

# Load all files in the mvnd directory (sorted for deterministic order)
Dir[File.join(__dir__, 'mvnd', '*.rb')].sort.each { |file| require file }