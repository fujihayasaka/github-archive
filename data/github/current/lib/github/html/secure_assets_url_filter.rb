# typed: true
# frozen_string_literal: true

module GitHub::HTML
  class SecureAssetsURLFilter < Filter
    def call
      return doc.to_html unless context[:secure_user_assets]

      doc.css("img").each do |element|
        filter = GitHub::Goomba::SecureAssetsURLFilter.new
        filter.call(element)
      end

      doc.to_html
    end
  end
end
