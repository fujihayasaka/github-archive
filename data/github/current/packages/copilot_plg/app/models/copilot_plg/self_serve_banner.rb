# typed: strict
# frozen_string_literal: true

module CopilotPLG
  class SelfServeBanner < ApplicationRecord::Domain::CopilotPLG
    self.table_name = "self_serve_banners"

    attr_readonly :slug

    validates :slug, presence: true, uniqueness: true
    validates :title, presence: true
    validates :body, presence: true
    validates :cta_url, presence: true, format: URI::DEFAULT_PARSER.make_regexp(%w[http https])
    validates :cta_text, presence: true
    validates :visibility, presence: true
  end
end
