# typed: true
# frozen_string_literal: true

module Gitignore

  def self.templates
    Dir["#{Rails.root}/vendor/gitignore/*.gitignore"].
      map    { |file| File.basename(file, ".gitignore") }.
      sort
  end

  def self.template(template = nil)
    if template && self.template_exists?(template)
      File.read("#{Rails.root}/vendor/gitignore/#{template}.gitignore")
    end
  end

  def self.template_exists?(template)
    self.templates.include?(template)
  end
end
